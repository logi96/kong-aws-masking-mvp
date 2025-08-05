return {
  name = "aws-masker",
  fields = {
    { config = {
        type = "record",
        fields = {
          { enabled = { type = "boolean", default = true } },
          { anthropic_api_key = { type = "string", required = false } },
          { redis_host = { type = "string", default = "redis" } },
          { redis_port = { type = "number", default = 6379 } },
          { mask_ec2_instances = { type = "boolean", default = true } },
        }
    }}
  }
}
