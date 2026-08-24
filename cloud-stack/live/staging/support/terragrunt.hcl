# Inherit from global environment.
include "env" {
  path = find_in_parent_folders("root.hcl")
}

# Treat this directory as a harmless unit so run-all can traverse it
# without hitting a plain Terraform root. This points to a no-op module.
terraform {
  source = "../../../modules/_noop"
}
