locals {
  all_tags      = toset(flatten([for key, value in var.instances : value.tags]))
  networks      = setintersection(local.all_tags, ["cephfs", "cephfs2"])
  network_names = {
    "cephfs"  = "CephFS-Network"
    "cephfs2" = "CephFS2-Network"
  }
  ceph_instances = {
    for name, instance in var.instances :
      name => instance
      if contains(instance.tags, "cephfs") || contains(instance.tags, "cephfs2")
  }

  ceph_online_instances = {
    for hostname, instance in var.instances : hostname => instance
    if !contains(instance.tags, "pool") || contains(var.pool, hostname)
  }
}

data "openstack_networking_network_v2" "cephfs_network" {
  for_each = local.networks
  name     = local.network_names[each.key]
}

data "openstack_networking_subnet_v2" "cephfs_subnet" {
  for_each = local.networks
  network_id = data.openstack_networking_network_v2.cephfs_network[each.key].id
}

resource "openstack_networking_secgroup_v2" "cephfs_sg" {
  for_each = local.networks
  name        = "${var.cluster_name}-${each.key}_sg"
  description = "${var.cluster_name} ${each.key} access security group"
}

resource "openstack_networking_secgroup_rule_v2" "mon_out" {
  for_each          = local.networks
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 3000
  port_range_max    = 3000
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key]
  description       = "Allow access to ${each.key} mon"
  security_group_id = openstack_networking_secgroup_v2.cephfs_sg[each.key].id
}

resource "openstack_networking_secgroup_rule_v2" "mon_out_flallback" {
  for_each          = local.networks
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6789
  port_range_max    = 6789
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key]
  description       = "Allow access to ${each.key} mon (fallback)"
  security_group_id = openstack_networking_secgroup_v2.cephfs_sg[each.key].id
}


resource "openstack_networking_secgroup_rule_v2" "daemon_out" {
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6800
  port_range_max    = 7100
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key]
  description       = "Allow access to ${each.key} OSD / MDS / MGR"
  security_group_id = openstack_networking_secgroup_v2.cephfs_sg[each.key].id
}

resource "openstack_networking_port_v2" "nic_ceph" {
  for_each           = local.ceph_instances
  name               = format("%s-%s-ceph-port", var.cluster_name, each.key)
  network_id         = contains(each.value.tags, "cephfs") ? data.openstack_networking_network_v2.cephfs.id : data.openstack_networking_network_v2.cephfs2.id
  security_group_ids = [data.openstack_networking_secgroup_v2.global.id]
}

resource "openstack_compute_interface_attach_v2" "extra_network" {
  for_each    = local.ceph_online_instances
  instance_id = each.value.id
  port_id     = openstack_networking_port_v2.nic_ceph[each.key].id
}

