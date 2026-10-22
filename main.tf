data "openstack_networking_network_v2" "cephfs" {
  name = "CephFS-Network"
}

data "openstack_networking_network_v2" "cephfs2" {
  name = "CephFS2-Network"
}

data "openstack_networking_secgroup_v2" "global" {
  name = "${var.cluster_name}-secgroup"
}

locals {
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

