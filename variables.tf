variable "cluster_name" {
  type        = string
  description = "Name of the cluster. Used to name the NICs"
}

variable "pool" {
  type        = list(string)
  description = "List of hostnames with pool tag that are online"
  default     = []
}

variable "instances" {
  type = object
  description = "Map of instances as output by Magic Castle OpenStack module"
}
