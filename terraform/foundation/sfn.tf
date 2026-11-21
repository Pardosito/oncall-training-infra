# Scenario state machine (ARCHITECTURE §6). Billed per state transition (~10 per session), not
# hourly, so it lives in foundation. Role = LabRole: the lab doesn't allow creating IAM roles.

data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${local.name}-scenario"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_sfn_state_machine" "scenario" {
  name     = "${local.name}-scenario"
  type     = "STANDARD"
  role_arn = data.aws_iam_role.lab.arn

  # jsondecode/jsonencode fails the plan on invalid JSON and stores a minified definition.
  definition = jsonencode(jsondecode(templatefile("${path.module}/../../statemachines/scenario.asl.json", {
    faults_queue_url       = module.faults.url
    user_actions_queue_url = module.user_actions.url
    sessions_table         = aws_dynamodb_table.sessions.name
  })))

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = false # inputs carry the task token
    level                  = "ERROR"
  }

  tags = local.tags
}
