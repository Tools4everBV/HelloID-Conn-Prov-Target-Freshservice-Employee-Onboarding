# HelloID-Conn-Prov-Target-FreshService
> [!IMPORTANT]
> This connector has been upgraded to a HelloID PowerShell v2 connector and refactored to meet the latest standards.
Please note that it was updated without a working test environment, so we recommend validating it during implementation.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="assets/logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-FreshService](#helloid-conn-prov-target-freshservice)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Onboard request](#onboard-request)
    - [Resource](#resource)
    - [Force property to type INT](#force-property-to-type-int)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-FreshService_ is a _target_ connector. The FreshService connector facilitates the creation of an onboarding request in Freshservice. Additionally, it creates departments if the department of the user does not yet exists.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                            | Remarks |
| ----------------------------------------- | --------- | ---------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Only creates an onboarding request |         |
| **Permissions**                           | ❌         | -                                  |         |
| **Resources**                             | ✅         | Creates departments                |         |
| **Entitlement Import: Accounts**          | ❌         | -                                  |         |
| **Entitlement Import: Permissions**       | ❌         | -                                  |         |
| **Governance Reconciliation Resolutions** | ❌         | -                                  |         |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-FreshService/refs/heads/main/Icon.png
```

### Requirements

**Token**:<br>
   Before using this connector, ensure you have the appropriate Authorization Token in order to connect to the API.


### Connection settings

The following settings are required to connect to the API.

| Setting            | Description                                   | Mandatory |
| ------------------ | --------------------------------------------- | --------- |
| AuthorizationToken | The Authorization Token to connect to the API | Yes       |
| BaseUrl            | The URL to the API                            | Yes       |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _FreshService_

## Remarks

### Onboard request
**No account creation**: The connector is responsible for generating an onboarding request rather than creating a user.

**No GET call**: The connector does not verify the presence of an active onboarding request since these requests are not deleted. Otherwise, when an employee returns, a new onboarding request would not be generated.

### Resource
**Create departments**: The connector utilizes the resource script to establish the departments.

**Resource configuration field**: The resource configuration should specifically choose the Department.DisplayName field.

### Force property to type INT
**cf_cost_center**: The `cf_cost_center` property is cast to an INT type in create.ps1 to meet API requirements.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                    | HTTP Method | Description                              |
| --------------------------- | ----------- | ---------------------------------------- |
| /api/v2/onboarding_requests | GET, POST   | Gets and creates the onboarding requests |
| /api/v2/locations           | GET         | Gets the locations                       |
| /api/v2/departments         | GET, POST   | Gets and creates the departments         |
| /api/v2/requesters          | GET         | Gets the requesters                      |
| /api/v2/agents              | GET         | Gets the agents                          |

### API documentation

[documentation](https://api.freshservice.com/#create_onboarding_request)

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
