# OrbWeaver

### Description

OrbWeaver is a lightweight mechanism to provide weaved stream abstraction, enabling opportunistic exploitation of IDLE cycles for in-network communication.

The repo contains an example OrbWeaver mechanism inline with a minimal p4 user program for a tofino pipeline with fully connected 100G quads, so that one could adapt the scripts based on the custom wiring, number of utilized pipelines and ports, and the target data plane application.
Metadata, actions, and tables with `*_` suffix are for debugging purposes only.

The prototype was developed on testbed with a pair of Wedge100BF-32X Tofino switch and `bf-sde-9.2.0`.
The repo provides the implementation in both p4v14 and p4v16.

### Further Questions

For more details, please refer to our NSDI 2022 paper: [OrbWeaver: Using IDLE Cycles in Programmable networks for Opportunistic Coordination](https://www.usenix.org/system/files/nsdi22-paper-yu.pdf).

```
@inproceedings {orbweaver,
author = {Liangcheng Yu and John Sonchack and Vincent Liu},
title = {OrbWeaver: Using IDLE Cycles in Programmable Networks for Opportunistic Coordination},
booktitle = {19th USENIX Symposium on Networked Systems Design and Implementation (NSDI 22)},
year = {2022},
isbn = {978-1-939133-27-4},
address = {Renton, WA},
pages = {1195--1212},
url = {https://www.usenix.org/conference/nsdi22/presentation/yu},
publisher = {USENIX Association},
month = apr,
}
```

Feel free to post [issues](https://github.com/eniac/OrbWeaver/issues) or contact `leoyu@seas.upenn.edu` if any question arises.

