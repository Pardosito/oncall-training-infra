# Sessions table (ARCHITECTURE §10.1). The item shape is owned by the backend
# (backend ARCHITECTURE §7.1); key and index names here are part of that contract.
resource "aws_dynamodb_table" "sessions" {
  name         = "Sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"
  range_key    = "session_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "scenario_id"
    type = "S"
  }

  attribute {
    name = "score"
    type = "N"
  }

  global_secondary_index {
    name            = "Leaderboard"
    projection_type = "ALL"

    key_schema {
      attribute_name = "scenario_id"
      key_type       = "HASH"
    }

    key_schema {
      attribute_name = "score"
      key_type       = "RANGE"
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  # AWS-owned key: encrypted at rest at no extra cost.
  server_side_encryption {
    enabled = false
  }

  deletion_protection_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}
