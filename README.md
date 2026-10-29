# C3G Elastic HPC subnet module for Magic Castle

This Terraform module creates OpenStack network ports for Magic Castle instances
and attaches them when the instances are considered online. It uses the existing
CephFS networks in Juno; it does not create networks or subnets.

## Inputs

| Variable | Description | Default |
| --- | --- | --- |
| `cluster_name` | Cluster name used in port and security group names. | Required |
| `instances` | Map of instances from the Magic Castle OpenStack module, keyed by hostname. Each entry must provide `tags` and an instance `id` for attachment. | Required |
| `pool` | Hostnames of instances tagged `pool` that are considered online. | `[]` |

## Network selection

The module collects all instance tags and selects the tags supported by
`local.network_names`:

| Instance tag | Existing OpenStack network |
| --- | --- |
| `cephfs` | `CephFS-Network` |
| `cephfs2` | `CephFS2-Network` |

Only networks referenced by at least one instance tag are looked up. The module
also looks up a subnet for each selected network using its network ID.

Each instance receives one port for each supported network tag it has. An
instance tagged with both `cephfs` and `cephfs2` receives two ports; an instance
with neither tag receives none. If no instances have supported tags, the module
creates no resources.

## Port creation and attachment

`local.nic_map` contains one entry per matching instance/network pair. Its key is
`<cluster_name>-<network_tag>-<hostname>-port`, which is also the port name. Each
entry records the network tag, instance, and whether it is considered online:

```hcl
online = !contains(instance.tags, "pool") || contains(var.pool, hostname)
```

| Instance tags and pool membership | Port created | Port attached |
| --- | --- | --- |
| Supported network tag, no `pool` tag | Yes | Yes |
| Supported network tag and `pool` tag, hostname in `var.pool` | Yes | Yes |
| Supported network tag and `pool` tag, hostname absent from `var.pool` | Yes | No |
| No supported network tag | No | No |

Online status is derived from these inputs, not queried from OpenStack. The
module creates ports from the full `nic_map`, then filters that map by `online`
to create interface attachments using each instance's ID and its port ID.

On a subsequent apply, removing a pool hostname from `var.pool` removes its
attachments while preserving its ports. Adding it back reuses those ports.
Removing a network tag from an instance removes the corresponding port and
attachment.

For example, with `cluster_name = "demo"` and `pool = ["worker1"]`:

| Hostname | Tags | Result |
| --- | --- | --- |
| `login1` | `cephfs` | `demo-cephfs-login1-port`, attached |
| `worker1` | `cephfs`, `cephfs2`, `pool` | One attached port on each CephFS network |
| `worker2` | `cephfs2`, `pool` | `demo-cephfs2-worker2-port`, unattached |

## Security groups

For each selected network, the module creates a security group named
`<cluster_name>-<network_tag>_sg` and assigns it to that network's ports. The
module explicitly adds these IPv4 TCP egress rules, with the selected subnet's
CIDR as their destination:

| Destination ports | Rule description |
| --- | --- |
| `3000` | Monitor access |
| `6789` | Monitor fallback access |
| `6800–7100` | OSD / MDS / MGR access |

## Requirements and resource identity

Requires Terraform `>= 1.5.7` and the
`terraform-provider-openstack/openstack` provider `>= 1.50.0`, configured by the
calling module. The named networks must already exist, and each subnet lookup
must resolve to a single subnet.

The generated port names are also Terraform `for_each` keys for ports and
attachments. Changing `cluster_name` or a hostname changes those resource
addresses and normally causes replacement unless the state addresses are migrated.

