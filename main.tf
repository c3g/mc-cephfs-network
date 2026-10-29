locals {
  network_names = {
    "cephfs"  = "CephFS-Network"
    "cephfs2" = "CephFS2-Network"
  }
  all_tags      = toset(flatten([for key, value in var.instances : value.tags]))
  networks      = setintersection(local.all_tags, keys(local.network_names))
  nic_map = merge([ for network in local.networks:
    {
      for hostname, instance in var.instances:
        format("%s-%s-%s-port", var.cluster_name, network, hostname) => {
          network  = network,
          instance = instance,
          online   = !contains(instance.tags, "pool") || contains(var.pool, hostname)
        } if contains(instance.tags, network)
    }
  ]...)
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
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key].cidr
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
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key].cidr
  description       = "Allow access to ${each.key} mon (fallback)"
  security_group_id = openstack_networking_secgroup_v2.cephfs_sg[each.key].id
}


resource "openstack_networking_secgroup_rule_v2" "daemon_out" {
  for_each          = local.networks
  direction         = "egress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6800
  port_range_max    = 7100
  remote_ip_prefix  = data.openstack_networking_subnet_v2.cephfs_subnet[each.key].cidr
  description       = "Allow access to ${each.key} OSD / MDS / MGR"
  security_group_id = openstack_networking_secgroup_v2.cephfs_sg[each.key].id
}

resource "openstack_networking_port_v2" "nic_ceph" {
  for_each           = local.nic_map
  name               = each.key
  network_id         = data.openstack_networking_network_v2.cephfs_network[each.value.network].id
  security_group_ids = [openstack_networking_secgroup_v2.cephfs_sg[each.value.network].id]
}

resource "openstack_compute_interface_attach_v2" "extra_network" {
  for_each    = { for k, v in local.nic_map: k => v if v.online }
  instance_id = each.value.instance.id
  port_id     = openstack_networking_port_v2.nic_ceph[each.key].id
}
