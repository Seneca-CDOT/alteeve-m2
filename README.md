# [Anvil!](https://www.alteeve.com/w/Anvil!) m2 - [Striker](https://www.alteeve.com/w/Striker) + [ScanCore](https://www.alteeve.com/w/ScanCore) v2.0.1

Welcome to the v2.0.0 release of the _Anvil!_ m2 [Intelligent Availability](https://www.alteeve.com/w/Intelligent_Availability)™ platform!

What is an _Anvil!_ platform?

- It is the first server platform designed with the singular focus of protecting your servers and keeping them running under even extreme fault conditions.
- It is fully self-contained, making it ideal for totally offline operation.
- It is a "self driving" server availability platform that can continuously monitors internal and external data sources, compiling, analyzing and autonomously deciding when and what action to take to protect your servers. It is ideally suited for extended remote deployments and "hands off" operation.
- It is based on an extensively field tested, open architecture with full data, mechanical and electrical redundancy allowing any component to be failed, removed and replaced without the need for a maintenance window. The _Anvil!_ platform has over five years of real-world deployment over dozens of sites and an historic uptime of over 99.9999%.
- It is extremely easy to use, minimizing the opportunity for human error and making it as simple as possible for "remote hands" to affect repairs and replacements without any prior availability experience and minimal technical knowledge.

In short, it is a server platform that just won't die.

- How do you build an _Anvil!_?

It's quite easy, but it does require a little more space than a README allows for.

- [How to Build an m2 _Anvil!_](https://www.alteeve.com/w/Build_an_m2_Anvil!)

The _Anvil!_ platform was designed and extensively tested on [Primergy](http://www.fujitsu.com/global/products/computing/servers/primergy/) servers, Brocade [ICX](http://www.brocade.com/en/products-services/switches/campus-network-switches.html) switches and APC [SmartUPS](http://www.apc.com/smartups/index.cfm?ISOCountryCode=ca) UPSes and [Switched PDU](http://www.apc.com/shop/ca/en/categories/power-distribution/rack-power-distribution/switched-rack-pdu/_/N-17k76am)s. That said, the _Anvil!_ platform is designed to be hardware agnostic and should work just fine on Dell, Cisco USC, NEC, Lenovo x-series, and other tier-1 server vendors.

[Alteeve](https://www.alteeve.com/), the company behind the _Anvil!_ project, actively supports the [open source](https://www.alteeve.com/w/Support) community. We also offer commercial support contracts to assist with any stage of deployment, operation and custom development.

# Actions for the AI

This section provides an overview of the components involved in supporting the "ScanCore AI".

## Overview

![Overview of the Action module working with the AI](./assets/scancore-ai-taking-action.png)

Two pieces have been added in order for the AI to dispatch actions and prevent interference when the dispatched actions are executed:

### 1. `execute-action` CLI tool

`execute-action` accepts an action number and executes the corresponding action. It takes following arguments in the form of switches:

1. (required) `--action [action code]`
2. (required) one of `--node [Node number]` or `--node-uuid [Node UUID]`, and
3. (optional) `--csv [action CSV]`, and
4. (optional) one of `--record` or `--record-only`

Note that:
* Node number starts from 1 instead of 0 (which would be referred to as "Node index").
* The length of the CSV matches `[number of actions] x [number of Nodes]`, where the first `[number of actions]` elements represents actions for the first Node, i.e., `1,0,0,0,0,0` is action assume on Node 1.
* Action CSV is only used when either `--record` or  `--record-only` is set. This switch is only for skipping the need to recreate the action array when it can be provided; keep in mind that the script will not disassemble and check whether the CSV matches the provided action or Node.
* `--record` will record the action and also execute the tasks defined for the action, but `--record-only` will record and exit without executing the defined tasks, i.e., server migration will be recorded but will not actually occur if this script was called with action assume and `--record-only`.

Example usage:

```
execute-action --action "U" --node "1"
```

### 2. `scancore::post_scan_checks::enabled` flag in `/etc/striker/striker.conf`

The `scancore::post_scan_checks::enabled` flag controls whether ScanCore should be analyzing the data collected by the scan agents and taking action based on the analysis. It can be set to:

- `0`: ignore post scan checks, or
- `1`: perform post scan checks

## Actions Definition

### Node Actions

These actions are only executed by **Nodes**.

| Code | Name   | Definition                                                                             |
| ---- | ------ | -------------------------------------------------------------------------------------- |
| A    | Assume | Migrate Anvil servers to the Node on which the action was executed.                    |
| D    | Down   | Shutdown a Node; it will be auto-removed from the cluster during the shutdown process. |

### Striker Actions

These actions are only executed by **Strikers**.

| Code | Name | Definition                                                                        |
| ---- | ---- | --------------------------------------------------------------------------------- |
| U    | Up   | Boot a Node; it will be auto-added to the cluster during the Node's boot process. |
