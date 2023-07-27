
# HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding
| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="assets/logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Freshservice-Employee-Onboarding_ is a _target_ connector. The Freshservice connector facilitates the creation of an onboarding request in Freshservice. Additionally, it creates departments if the department of the user does not yet exists.

| Endpoint     | Description |
| ------------ | ----------- |
| /api/v2/onboarding_requests | Gets and created the onboarding requests (GET, POST) |
| /api/v2/locations | Gets the locations (GET) |
| /api/v2/departments | Gets and creates the departments (GET, POST)  |
| /api/v2/requesters | Gets the requesters (GET) |
| /api/v2/agents | Gets the agents (GET) |

The following lifecycle events are available:

| Event  | Description | Notes |
| ------ | ----------- | ----- |
| create.ps1 | Create an onboarding request | - |
| update.ps1 | | N/A. |
| enable.ps1 | | N/A. |
| disable.ps1 | | N/A. |
| delete.ps1 | | N/A. |
| resource.ps1 | Create the departments | - |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| AuthorizationToken     | The Authorization Token to connect to the API | Yes         |

### Prerequisites
- Before using this connector, ensure you have the appropriate Authorization Token in order to connect to the API.

### Remarks
- The connector is responsible for generating an onboarding request rather than creating a user.
- The connector does not verify the presence of an active onboarding request since these requests are not deleted. Otherwise, when an employee returns, a new onboarding request would not be generated.
- The connector utilizes the resource script to establish the departments.
- The resource configuration should specifically choose the Department.DisplayName field.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
