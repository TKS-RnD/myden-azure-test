# Overview
The repository contains code that tries to accomplish the following:
1. Bootstrap infrastructure required to run Terraform for Denave.
2. Single Sign-on for Denave where Azure AD functions as an Identity provider for GCP Cloud and AWS Cloud.
3. Signed Scripts Infrastructure that allows administrators to run scripts that are pre-approved and verified.
4. Application Environment to run Denave Internal applications within Azure safely via best practices.
.
To follow what every one of the above steps do, individual recipe documentation must be consulted as listed below:

## Bootstrap
The bootstrap steps are listed in [bootstrap folder.](bootstrap/README.md). The list of recipes in that folder must be
executed in order:
1. Creation of Bucket for storing terraform state by running the powershell script.
2. Creation of Intermediate Proxy App.
3. Creation of Terraform Administrator group, role and enabling it for PIM.

The expectation here is Bootstrap recipes are to be used only by the Super Administrator in Denave.

## MyDen Application
The MyDen Application is a list of recipes which needs to be executed in the following order:
1. Image builders for both the [Application VM](myden-app/vm-image/README.md) and the Database VM.
2. Launching the DB and App VM and connecting them within the subnet.

## Single Sign on for GCP
The [single sign on recipe](single-sign-on/gcp-sso-app.tf) is used for linking GCP with Azure AD. Further instructions are available in [README](single-sign-on/README.md).
