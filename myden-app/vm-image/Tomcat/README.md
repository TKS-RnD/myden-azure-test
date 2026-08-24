# Tomcat 9.0 Configuration Files – README

This document explains the folder structure inside **`tomcat9.0.89`**, along with the purpose of each configuration file.  
These files must be copied into the **default Tomcat installation** after setup, as they contain security settings, custom pages, and updated configurations.

---

## 📁 Folder Structure Overview
```
tomcat9.0/
└── apache-tomcat-9.0.89/
├── conf/
│ ├── server.xml
│ ├── tomcat-users.xml
│ └── web.xml
└── webapps/
├── ROOT/
│ ├── error.jsp
│ ├── favicon.ico (remove default one before replacing)
│ └── REMOVE the default index.jsp from this folder
└── manager/
└── META-INF/
└── context.xml
```

---

## 1. Folder: `apache-tomcat-9.0.89/`

This is the main directory containing configuration files and deployable components for Tomcat.

---

## 2. Folder: `conf/`

Contains core Tomcat configuration files. These must be placed inside the `conf` directory of your Tomcat installation.

### **server.xml**
- Primary configuration file of Tomcat  
- Defines connectors (HTTP/HTTPS), ports, services, and virtual hosts  
- Any change impacts Tomcat's global runtime behavior

### **tomcat-users.xml**
- Stores user credentials and assigned roles  
- Required for accessing the **Manager** and **Host Manager** applications  
- Important for access control and security

### **web.xml**
- Global deployment descriptor for all applications  
- Defines servlet mappings, MIME types, and error-page settings  
- Used to enforce global configurations and security rules

---

## 3. Folder: `webapps/`

Contains all web applications deployed on Tomcat.

---

### 3.1 Folder: `webapps/ROOT/`

This is the default application served at:

http://<server>:<port>/


#### **error.jsp**
- Custom error page  
- Used to replace Tomcat's default error messages  
- Helps hide server details and improve security

#### **favicon.ico**
- Replace Tomcat’s default favicon with your application icon  
- Delete the existing default favicon before replacing it

---

### 3.2 Folder: `webapps/manager/META-INF/`

#### **context.xml**
- Manages context-level configuration for the **Manager** application  
- Often customized for security restrictions, access rules, and deployment control  
- Overrides the default file provided by Tomcat

---

## 🔐 Why These Files Must Be Replaced

Replacing these default files ensures:

- Improved application and server security  
- Custom branding (favicon, error pages)  
- Correct user and role configuration  
- Standardized configuration across environments

---

## 📦 Deployment Instructions

1. Install Tomcat 9.0.
2. Go to the Tomcat installation directory (example: `/opt/tomcat/`).
3. Replace the following files/folders:

conf/server.xml
conf/tomcat-users.xml
conf/web.xml
webapps/ROOT/error.jsp
webapps/ROOT/favicon.ico
webapps/manager/META-INF/context.xml


4. Restart Tomcat:

systemctl restart tomcat


---

## ✅ Summary

This folder contains **security-enhanced and pre-configured Tomcat files**.  
Copy them into your Tomcat installation to maintain consistent and secure configurations across all team environments.

---

