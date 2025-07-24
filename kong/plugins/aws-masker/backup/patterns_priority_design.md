# 패턴 우선순위 설계 문서

## 우선순위 할당 원칙

1. **낮은 숫자 = 높은 우선순위** (먼저 처리됨)
2. **긴 패턴/구체적 패턴**이 짧은 패턴보다 우선
3. 동일한 리소스의 ARN 형식이 ID 형식보다 우선

## 우선순위 그룹

### Priority 100-199: ARN 패턴 (가장 구체적)
- lambda_arn: 100
- ecs_task: 105
- elb_arn: 110
- iam_role: 115
- iam_user: 120
- kms_key: 125
- cert_arn: 130
- secret_arn: 135
- parameter_arn: 140
- codecommit: 145
- dynamodb_table: 150
- sns_topic: 155
- sqs_queue: 160
- stack_id: 165
- kinesis: 170
- elasticsearch: 175
- states_machine: 180
- batch_job: 185
- athena: 190
- arn (generic): 195

### Priority 200-299: 긴 ID 패턴 (16-32자리)
- nat_gateway (32자리): 200
- ebs_volume (17자리): 210
- subnet (17자리): 220
- vpc (17자리): 230
- security_group (17자리): 240
- ec2_instance (17자리): 250
- ami (16자리): 260
- efs_id (17자리): 270
- igw (17자리): 280
- vpn (17자리): 285
- tgw (17자리): 290
- snapshot (17자리): 295

### Priority 300-399: 중간 길이 패턴
- api_gateway (10자리+도메인): 300
- access_key (AKIA+16자리): 310
- route53_zone (Z+13자리): 320
- ecr_uri: 330
- log_group: 340

### Priority 400-499: IP 주소 패턴
- ipv6: 400
- private_ip_172: 410
- private_ip_172_2: 420
- private_ip_172_3: 430
- private_ip_192: 440
- private_ip (10.x): 450
- public_ip: 460

### Priority 500-599: 일반 문자열 패턴
- s3_bucket: 500
- s3_logs_bucket: 510
- rds_instance: 520
- elasticache: 530
- eks_cluster: 540
- redshift: 550
- glue_job: 560
- sagemaker: 570

### Priority 600+: 가장 일반적인 패턴
- account_id (12자리 숫자): 600
- session_token (base64): 610
- secret_key: 620

## 구현 고려사항

1. **Subnet 패턴 수정 필요**: 현재 8자리 → 17자리로 변경
2. **Public IP 패턴 수정 필요**: Lua 패턴 문법 오류 수정
3. **패턴 중복 방지**: 이미 매칭된 위치는 다시 매칭하지 않도록 처리