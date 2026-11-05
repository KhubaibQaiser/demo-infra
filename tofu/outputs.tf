output "pages_urls" {
  value = { for k, p in cloudflare_pages_project.site : k => "https://${p.subdomain}" }
}

# CNAME target check: must equal renderService in sites.json (Render may add a suffix on name collision).
output "render_urls" {
  value = { for k, r in render_web_service.api : k => r.url }
}

output "db_hosts" {
  value = { for k, d in aiven_mysql.db : k => d.service_host }
}

# Used by scripts/import-demo-db.sh only. Sensitive: never printed by CI.
output "db_connection" {
  sensitive = true
  value = { for k, d in aiven_mysql.db : k => {
    host     = d.service_host
    port     = d.service_port
    user     = d.service_username
    password = d.service_password
    database = "defaultdb"
    ca_cert  = data.aiven_project.this.ca_cert
  } }
}
