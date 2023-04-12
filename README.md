# Docker & Vault Agent with Terraform

```
terraform apply --target=docker_container.vault
```

```
terraform apply
```

In case you see this message, that means containers are not up and ready so just try terraform apply again.

```
╷
│ Error: error configuring database connection "mysql/config/items": Error making API request.
│ 
│ URL: PUT http://localhost:8200/v1/mysql/config/items
│ Code: 400. Errors:
│ 
│ * error creating database object: error verifying - ping: dial tcp 172.29.0.4:3306: connect: connection refused
│ 
│   with vault_database_secrets_mount.mysql,
│   on main.tf line 258, in resource "vault_database_secrets_mount" "mysql":
│  258: resource "vault_database_secrets_mount" "mysql" {
│
```


