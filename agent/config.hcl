pid_file = "/tmp/pidfile"

auto_auth {
  method {
    type = "approle"

    config = {
      role_id_file_path = "/agent/role-id"
      secret_id_file_path = "/agent/secret-id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink {
    type = "file"
    config = {
      path = "/tmp/.token"
      mode = 0644
    }
  }
}

template {
  source = "/agent/kv.tmpl"
  destination = "/usr/share/nginx/html/kv.html"
}

template {
  source = "/agent/psql.tmpl"
  destination = "/usr/share/nginx/html/psql.html"
}

template {
  source = "/agent/mysql.tmpl"
  destination = "/usr/share/nginx/html/mysql.html"
}

template {
  source = "/agent/rails.tmpl"
  destination = "/usr/share/nginx/html/rails.yaml"
}

vault {
  address = "http://vault:8200"
}
