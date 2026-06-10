-- Run as an Azure SQL administrator after infrastructure deployment.
-- Replace the app service name with the managed identity display name output by deployment.
CREATE USER [app-REPLACE-WITH-APP-SERVICE-NAME] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
ALTER ROLE db_datawriter ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
ALTER ROLE db_ddladmin ADD MEMBER [app-REPLACE-WITH-APP-SERVICE-NAME];
