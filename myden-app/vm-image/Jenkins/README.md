# Source Code Management (SCM) – SVN Repository

Steps:
Open Jenkins → Create a new Job or configure an existing one.

# 1. Under Source Code Management, select Subversion.

Provide the SVN repository URL.
Example:
```
https://svn.example.com/project/trunk
```

Add credentials if required (username/password or certificate-based).

Set the appropriate checkout strategy.

This allows Jenkins to pull the latest source code from the SVN repository.


# 2. Build Trigger
Setting:
```
	Check Build whenever a SNAPSHOT dependency is built
```
This trigger ensures Jenkins automatically starts a build whenever a related SNAPSHOT dependency is updated in the repository.


# 3. Build Environment Settings

Enable the following options:

Ensures the workspace is clean before every build. Avoids leftover files from previous builds causing issues.

```
a. Delete workspace before build starts
```

Adds readable timestamps to the Jenkins logs. Helps in debugging build timelines and delays.

```
b. Add timestamps to the Console Output
```

# 4. Maven Build Configuration

Root POM: <<Added pom.xmlin the Jenkins folder>>
```
pom.xml
```
Goals and Options:
```
clean install
```
Explanation:

clean: Removes previous build artifacts.

install: Compiles the code, runs tests, and installs the package into the local Maven repository.

Output of this step will include the WAR file that will be deployed later.


Ensure Maven is configured in Jenkins (Global Tool Configuration).

# 5. Post Steps
Setting:
```
	Run regardless of build result
```
This ensures the configured post steps execute even if the build succeeds, fails, or is unstable.

Useful for cleanup or deployment that must run under all circumstances.

# 6. Post-build Actions

a. WAR/EAR Files. Add:
```
**/*.war
```

This tells Jenkins to archive or deploy any WAR file created in any folder in the workspace.

b. Deployment to Tomcat 9.x (Remote)
Settings:

Container Type: ```Tomcat 9.x Remote```

Credentials: Use the credentials configured in Jenkins (e.g., mydenstaging creds)

Tomcat Manager URL:
```
https://mydenstaging.xyz.com:8443/
```
Notes:

Ensure the remote Tomcat server has the Tomcat Manager App enabled.

The Jenkins credentials must match a user in tomcat-users.xml with roles:

manager-script
manager-gui



Jenkins will automatically upload and deploy the WAR file to the specified Tomcat instance after the build completes.


# myDEN POM.xml file
All the dependencies along with their versions




