# Python IIS Deploy
This script automates the deployment of a Python application to an IIS server using fastcgi. It assumes the script lives in a /Scripts folder within a project root. Feel free to customize it for your purposes.

## Interesting learnings
1. Contrary to the documents fastCGI must be configured at the applicationHost level (applicationHost.config)
1. However, fastCGI handlers may be configured at the website level (web.config)
1. Unfortunately, attempting to add a handler to the webconfig using -PSPath does not work and the only way is to manually change your path to your website
