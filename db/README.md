# Representation Grant DB

## Overview

Representation Grant DB is used to store ...

## Development

The DB component is an instance of Postgres. The schema and data loading is all handled by Representation Grant API, and the Postgres image being used is an unchanged Red Hat image. As such, there is no build or database initialization associated with the DB - just the Deployment.

## Development

To deploy Representation Grant on an instance of OpenShift, see [the instructions](../RunningLocal.md) in the file RunningLocal.md.