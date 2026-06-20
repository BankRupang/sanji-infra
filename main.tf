terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# 무작위 ID를 생성하는 리소스
resource "random_id" "server" {
  byte_length = 8
}

# 생성된 ID를 출력
output "server_id" {
  value = random_id.server.hex
}
