# HelloID-Conn-Prov-Target-OrtecWS-SOAP

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.
>

> [!IMPORTANT]
> This connector requires a direct HR integration for the employee within Ortec WS. Without this integration, the connector cannot be implemented.

> [!IMPORTANT]
> This connector requires an on-premise HelloID Agent to be installed and running. In addition, the IP addresses of the HelloID Agent server must be whitelisted by Ortec. Please contact Ortec support to arrange this.


<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-OrtecWS-SOAP](#helloid-conn-prov-target-ortecws-soap)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [ExternalId (employeeNumber)](#externalid-employeenumber)
    - [EmployeeAccount](#employeeaccount)
    - [Adding and updating data](#adding-and-updating-data)
      - [Unexplainable error when updating the _userName_](#unexplainable-error-when-updating-the-username)
    - [Enable and disable accounts](#enable-and-disable-accounts)
    - [Importing accounts](#importing-accounts)
    - [Incomplete role authorization data](#incomplete-role-authorization-data)
    - [Error handling](#error-handling)
  - [Development resources](#development-resources)
    - [WSDL / SOAP calls](#wsdl--soap-calls)
    - [SOAP calls](#soap-calls)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-OrtecWS-SOAP_ is a _target_ connector. _Ortec-WS_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅         | Retrieve, Grant, Revoke                 |         |
| **Resources**                             | ❌         | -                                       |         |
| **Entitlement Import: Accounts**          | ✅         | -                                       |         |
| **Entitlement Import: Permissions**       | ✅         | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅         | -                                       |         |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-OrtecWS-SOAP/refs/heads/main/Icon.png
```

### Connection settings

The following settings are required to connect to the API.

| Setting     | Description                                                | Mandatory |
| ----------- | ---------------------------------------------------------- | --------- |
| BaseUrl     | The URL to the API                                         | Yes       |
| ApiUserName | The username used for authenticating with the OrtecWS API. | Yes       |
| ApiPassword | he password associated with the API username.              | Yes       |
| Psk         | The Psk to connect to the API                              | Yes       |


### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Ortec-WS_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `employeeNumber`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `employeeNumber` property from _Ortec-WS_

## Remarks

### ExternalId (employeeNumber)

The `ExternalId` (employeeNumber) is managed by the external HR system.

### EmployeeAccount

To be able to create a user account in OrtecOWS, an EmployeeAccount is required.

> [!NOTE]
> EmployeeAccounts are not created by the connector itself, but are provisioned through a direct HR sync process.

### Adding and updating data

The Ortec-WS API can also be noticeably slow when creating or updating user data or user properties. Write operations (such as user creation or updates) tend to have higher response latency compared to simple retrieval calls.

#### Unexplainable error when updating the _userName_

When updating the _userName_ field, we sometimes received error: _Exceptions_ with result: _NACK_. The cause of this error is currently unknown.

### Enable and disable accounts

When enabling and/or disabling the account, the _userName_ must always be inluded in the enable/update request. Be aware that;
- An empty userName will result in error: '_Exceptions_ with result: _NACK_'.
- A _userName_ that is incorrect returns _ACK_ indicating that the request was succesful. However, the account will not be enabled/disabled.

### Importing accounts

It is not possible to retrieve all authorizations or entitlements in a single request from the Ortec-WS API. Instead, authorizations must be retrieved on a per-user basis.

This means that the import process needs to:

- First retrieve the full list of users from Ortec-WS
- For each individual user, call the _HelloID_GetUserAuthorizations_ operation
- Extract the roles (authorizations) assigned to that specific user
- Build a mapping between roleId → employeeNumber(s) during processing
- After processing all users, retrieve the full list of available roles using _HelloID_GetAuthorizations_
- Combine both datasets to construct the final entitlement output, including:
- Role metadata (name, description, etc.)
- Linked accounts per role

> [!NOTE]
> Because authorizations are only available per user, the import process is inherently iterative and user-driven. This makes performance dependent on the number of users.

### Incomplete role authorization data

It is possible that users exist with assigned roles that are not returned by the _HelloID_GetAuthorizations_ action. In these cases, the entitlement import process may fail (snapshot won't be created) due to missing role definitions. To ensure a stable entitlement import, these roles may need to be excluded from the entitlement import process.

> [!NOTE]
> This behavior has been identified for roleIds `1` and `6` within our test environment.

### Error handling

Error handling in the current implementation is limited. Errors returned by the Ortec-WS actions are not consistently normalized or enriched with context.

## Development resources

### WSDL / SOAP calls

The WSDL / SOAP calls are used by the connector

### SOAP calls

| SOAP call                     | Description            | Lifecycle action                                                                                                   |
| ----------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------ |
| HelloID_GetUser               | Retrieve users         | Create,Enable,Disable,Update,GrantPermission,RevokePermission,AccountEntitlementImport,PermissionEntitlementImport |
| HelloID_AddUser               | Create a new user      | Create                                                                                                             |
| HelloID_UpdateUser            | Update a user          | Update,Enable,Disable                                                                                              |
| HelloID_GetAuthorizations     | Retrieve authorzations | PermissionEntitlementImport,Permissions                                                                            |
| HelloID_GetUserAuthorizations | Retrieve authorzations | PermissionEntitlementImport                                                                                        |

### API documentation

The Ortec-WS API documentation is not publicly available. It is provided on request or via internal/vendor documentation channels.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
