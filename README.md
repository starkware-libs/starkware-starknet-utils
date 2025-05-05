
<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/starknet-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/starknet-light.png">
  <img alt="Starknet" src="assets/starknet-light.png">
</picture>
</div>

<div align="center">
[![License: Apache2.0](https://img.shields.io/badge/License-Apache2.0-green.svg)](LICENSE)
</div>

# StarkWare Utils <!-- omit from toc -->

## Table of contents <!-- omit from toc -->

 <!-- omit from toc -->
- [About](#about)
- [Disclaimer](#disclaimer)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Getting help](#getting-help)
- [Audit](#audit)
- [Security](#security)

## About

This repo holds the implementation of the Starknet apps common library (starkware_utils).

## Disclaimer

This is a work in progress.

## Dependencies

The project is built with [Scarb](https://docs.swmansion.com/scarb/) and [Starknet foundry](https://foundry-rs.github.io/starknet-foundry/index.html).

## Installation

To use this package in your project, add the following to your `Scarb.toml` file:

```toml
[dependencies]
starkware_utils = { git = "https://github.com/starkware-libs/starkware-starknet-utils" version = SOME_VERSION }
...other dependencies...
```

## Getting help

Reach out to the maintainer at any of the following:

- [GitHub Discussions](https://github.com/starkware-libs/starkware-starknet-utils/discussions)
- Contact options listed on this [GitHub profile](https://github.com/starkware-libs)

## Audit

Find the latest audit report in [docs/audit](docs/audit).

## Security

StarkWare Utils follows good practices of security, but 100% security cannot be assured. StarkWare Utils is provided "as is" without any warranty. Use at your own risk.

For more information and to report security issues, please refer to our [security documentation](https://github.com/starkware-libs/starkware-starknet-utils/blob/main/docs/SECURITY.md).
