resource "ovh_cloud_project_storage" "s3_bucket" {
  service_name  = var.os_tenant_id
  region_name = keys(var.regions)[0]
  name = "potti-temporary-bucket"
}

resource "ovh_cloud_project_user" "s3_user" {
  service_name  = var.os_tenant_id
  role_name	= "objectstore_operator"
  description = "potti-temporary-bucket-user"
  depends_on = [ ovh_cloud_project_storage.s3_bucket ]
}

resource "ovh_cloud_project_user_s3_credential" "s3_user_cred" {
  service_name  = var.os_tenant_id

  user_id	= ovh_cloud_project_user.s3_user.id
  depends_on = [ ovh_cloud_project_user.s3_user ]
}

resource "ovh_cloud_project_user_s3_policy" "s3_user_policy" {
  service_name = var.os_tenant_id
  user_id      = ovh_cloud_project_user.s3_user.id
  policy = jsonencode({
    "Statement": [{
      "Action": ["s3:*"],
      "Effect": "Allow",
      "Resource": ["arn:aws:s3:::${ovh_cloud_project_storage.s3_bucket.name}","arn:aws:s3:::${ovh_cloud_project_storage.s3_bucket.name}/*"],
      "Sid": "AdminContainer"
    }]
  })

  depends_on = [ ovh_cloud_project_user.s3_user ]

}

output "s3_user_credential_access_key" {
  value = ovh_cloud_project_user_s3_credential.s3_user_cred.access_key_id
  sensitive = true
}

output "s3_user_credential_secret_key" {
  value = ovh_cloud_project_user_s3_credential.s3_user_cred.secret_access_key
  sensitive = true
}

# CORS configuration for the S3 bucket
# Note: OVH provider doesn't support CORS natively, so we use a null_resource with AWS CLI
resource "null_resource" "s3_cors_configuration" {
  triggers = {
    bucket_name = ovh_cloud_project_storage.s3_bucket.name
    cors_hash   = md5(jsonencode(var.s3_cors_rules))
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > /tmp/cors-config-${ovh_cloud_project_storage.s3_bucket.name}.json << 'EOF'
      {
        "CORSRules": ${jsonencode(var.s3_cors_rules)}
      }
      EOF
      
      AWS_ACCESS_KEY_ID="${ovh_cloud_project_user_s3_credential.s3_user_cred.access_key_id}" \
      AWS_SECRET_ACCESS_KEY="${ovh_cloud_project_user_s3_credential.s3_user_cred.secret_access_key}" \
      aws s3api put-bucket-cors \
        --bucket "${ovh_cloud_project_storage.s3_bucket.name}" \
        --cors-configuration file:///tmp/cors-config-${ovh_cloud_project_storage.s3_bucket.name}.json \
        --endpoint-url "https://s3.${lower(keys(var.regions)[0])}.io.cloud.ovh.net"
      
      rm -f /tmp/cors-config-${ovh_cloud_project_storage.s3_bucket.name}.json
    EOT
  }

  depends_on = [
    ovh_cloud_project_storage.s3_bucket,
    ovh_cloud_project_user_s3_credential.s3_user_cred,
    ovh_cloud_project_user_s3_policy.s3_user_policy
  ]
}