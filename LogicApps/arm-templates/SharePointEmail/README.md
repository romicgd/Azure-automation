# Templates to automate Logic Apps


- ```SharePointEmail``` folder - send email to specified accounts when file is added to SharePoint Online  site folder. Just replace ```%your-sharepoint-online-tenant%``` with your SharePoint online tenant in ```variables``` section of ARM template


``` 
    "variables": {
        "sharepoint_tenant_url": "https://%your-sharepoint-online-tenant%/sites"
    },
```
