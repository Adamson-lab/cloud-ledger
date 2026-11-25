# Copy to ~/.steampipe/config/azure.spc. Uses your `az login` session or a workload identity.
connection "azure" {
  plugin      = "azure"
  type        = "aggregator"
  connections = ["azure_*"]
}

connection "azure_prod" {
  plugin          = "azure"
  subscription_id = "REPLACE-WITH-SUBSCRIPTION-ID"
}
