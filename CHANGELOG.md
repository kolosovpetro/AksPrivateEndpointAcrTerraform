# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning v2.0.0](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - In Progress

### Changed

- Provision VNET and AKS nodes subnet
- Provision ACR with: `network_rule_set { default_action = "Deny" }` and `network_rule_bypass_option = "None"`
- Provision Private endpoint inside AKS nodes subnet
- Provision private DNS zone
- Configure DNS record that points to private endpoint internal IP address
- Link private DNS zone to VNET
- Provision AKS cluster with nodes inside AKS subnet
- Create ACR role assignment
