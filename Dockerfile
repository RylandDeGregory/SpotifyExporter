# Azure Functions PowerShell base image.
# Available tags: https://mcr.microsoft.com/en-us/artifact/mar/azure-functions/powershell/tags
FROM mcr.microsoft.com/azure-functions/powershell:4.1052.200-1-powershell7.6@sha256:85b2e9bbbbb20238137d2566c258e56b5072c18e997f91d8dc217d73edc7e0b5

# The Functions host loads the app from this path inside the container.
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true

COPY src/ /home/site/wwwroot/
