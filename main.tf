
data "template_file" "vault_configuration" {
  template = file("${path.cwd}/vault/config/vault.hcl")
}

data "template_file" "agent_configuration" {
  template = file("${path.cwd}/agent/config.hcl")
  vars = {
    role_id = "${vault_approle_auth_backend_role.role.role_id}"
    secret_id = "${vault_approle_auth_backend_role_secret_id.secret.secret_id}"
  }
}

data "docker_image" "nginx" {
  name = "nginx"
}

data "docker_image" "vault" {
  name = "vault"
}

data "docker_image" "postgres" {
  name = "hashicorpdemoapp/product-api-db:v0.0.22"
}

data "docker_image" "mysql" {
  name = "hashicorp/mysql-portworx-demo"
}

resource "docker_volume" "shared_volume" {
  name = "nginx"
}

resource "docker_network" "private_network" {
  name = "vault"
}

resource "docker_container" "vault" {
  name  = "vault"
  image = data.docker_image.vault.id

  command = ["vault", "server", "-dev", "-log-level=trace"]

  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=root",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200",
    "VAULT_API_ADDR=http://0.0.0.0:8200"
  ]

  ports {
    internal = "8200"
    external = "8200"
  }

  capabilities {
    add = ["IPC_LOCK"]
  }

  healthcheck {
    test         = ["CMD", "vault", "status"]
    interval     = "10s"
    timeout      = "2s"
    start_period = "10s"
    retries      = 2
  }

  upload {
    content = data.template_file.vault_configuration.rendered
    file    = "/vault/config/vault.hcl"
  }

  networks_advanced {
    name = docker_network.private_network.name
    aliases = ["vault"]
  } 

}

resource "docker_container" "agent" {
  name  = "vault-agent"
  image = data.docker_image.vault.id

  command = ["vault", "agent", "-config=/agent/config.hcl"]

  env = [
    "VAULT_ADDR=http://vault:8200",
  ]

  volumes {
    host_path      = "${path.cwd}/agent"
    container_path = "/agent"
  }

  volumes {
    host_path      = "${path.cwd}/nginx"
    container_path = "/usr/share/nginx/html"
  }

  capabilities {
    add = ["IPC_LOCK"]
  }

  networks_advanced {
    name = docker_network.private_network.name
  } 

  upload {
    content     = vault_approle_auth_backend_role.role.role_id
    file = "/agent/role-id"
  }

  upload {
    content     = vault_approle_auth_backend_role_secret_id.secret.secret_id
    file = "/agent/secret-id"
  }
}

resource "docker_container" "nginx" {
  name  = "nginx"
  image = data.docker_image.nginx.id
  
  ports {
    internal = "80"
    external = "80"
  }

  volumes {
    host_path      = "${path.cwd}/nginx"
    container_path = "/usr/share/nginx/html/"
  }
}

resource "docker_container" "postgres" {
  name  = "postgres"
  image = data.docker_image.postgres.id

  env = [
    "POSTGRES_DB=products",
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=pass"
  ]
  networks_advanced {
    name = docker_network.private_network.name
    aliases = ["postgres"]
  } 

}

resource "docker_container" "mysql" {
  name  = "mysql"
  image = data.docker_image.mysql.id

  env = [
    "MYSQL_ROOT_PASSWORD=pass"
  ]
  networks_advanced {
    name = docker_network.private_network.name
    aliases = ["mysql"]
  } 
}

data "vault_policy_document" "nginx" {
  rule {
    path         = "secret/data/nginx/*"
    capabilities = ["read", "list"]
    description  = "Read secrets for Nginx"
  }
  rule {
    path         = "postgres/creds/nginx"
    capabilities = ["read"]
    description  = "Generate PostgreSQL database credentials"
  }
  rule {
    path         = "mysql/creds/nginx"
    capabilities = ["read"]
    description  = "Generate MySQL database credentials"
  }
}

resource "vault_policy" "nginx" {
  name = "nginx-policy"

  policy = data.vault_policy_document.nginx.hcl

  depends_on = [
    docker_container.vault
  ]
}

resource "vault_auth_backend" "approle" {
  type = "approle"

  depends_on = [
    docker_container.vault
  ]
}

resource "vault_approle_auth_backend_role" "role" {
  backend        = vault_auth_backend.approle.path
  role_name      = "nginx"
  token_policies = ["default", "nginx-policy"]

  depends_on = [
    docker_container.vault
  ]
}

resource "vault_approle_auth_backend_role_secret_id" "secret" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.role.role_name

  depends_on = [
    docker_container.vault
  ]
}

resource "vault_kv_secret_v2" "nginx" {
  mount                      = "secret"
  name                       = "nginx/front-page"
  data_json                  = jsonencode(
  {
    app            = "nginx"
    username       = "zap",
    password       = "bar"
  }
  )
}

resource "vault_database_secrets_mount" "postgres" {
  path = "postgres"

  postgresql {
    name           = "products"
    username       = "postgres"
    password       = "pass"
    connection_url    = "postgresql://{{username}}:{{password}}@postgres:5432/products"
    allowed_roles = [
      "nginx",
    ]
  }

  depends_on = [
    docker_container.vault,
    docker_container.postgres
  ]
}

resource "vault_database_secret_backend_role" "postgres_nginx" {
  name    = "nginx"
  backend = vault_database_secrets_mount.postgres.path
  db_name = vault_database_secrets_mount.postgres.postgresql[0].name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
  ]
}

resource "vault_database_secrets_mount" "mysql" {
  path = "mysql"

  mysql {
    name           = "items"
    username       = "root"
    password       = "pass"
    connection_url    = "{{username}}:{{password}}@tcp(mysql:3306)/"
    allowed_roles = [
      "nginx",
    ]
  }

  depends_on = [
    docker_container.vault,
    docker_container.mysql
  ]
}

resource "vault_database_secret_backend_role" "mysql_nginx" {
  name    = "nginx"
  backend = vault_database_secrets_mount.mysql.path
  db_name = vault_database_secrets_mount.mysql.mysql[0].name
  
  creation_statements = [
    "CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';",
    "GRANT SELECT ON *.* TO '{{name}}'@'%';"
  ]
}


