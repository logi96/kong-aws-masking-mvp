#!/usr/bin/env python3
"""
Test Data Generator for P0 Risk Test Cases
Generates various edge case test data for AWS resource masking
"""

import json
import random
import string
import sys
from datetime import datetime

class TestDataGenerator:
    """Generate test data for various edge cases"""
    
    def __init__(self):
        self.aws_regions = [
            "us-east-1", "us-west-2", "eu-west-1", "ap-northeast-1",
            "ap-northeast-2", "ap-southeast-1", "eu-central-1"
        ]
        
    def generate_ec2_instance_id(self, valid=True):
        """Generate EC2 instance ID"""
        if valid:
            # Valid format: i-[0-9a-f]{17}
            return f"i-{''.join(random.choices('0123456789abcdef', k=17))}"
        else:
            # Invalid patterns
            invalid_patterns = [
                "i-",  # Too short
                "i-123",  # Too short
                f"i-{''.join(random.choices('0123456789abcdef', k=18))}",  # Too long
                f"i-{''.join(random.choices('ghijklmnop', k=17))}",  # Invalid chars
                "ec2-instance-123",  # Wrong format
            ]
            return random.choice(invalid_patterns)
    
    def generate_s3_bucket_name(self, edge_case=None):
        """Generate S3 bucket name with various edge cases"""
        if edge_case == "min_length":
            return "abc"  # 3 chars minimum
        elif edge_case == "max_length":
            # 63 chars maximum
            return ''.join(random.choices(string.ascii_lowercase + string.digits + '-', k=63))
        elif edge_case == "dots":
            return f"my.bucket.with.dots.{random.randint(1000, 9999)}"
        elif edge_case == "consecutive_dots":
            return "my..invalid..bucket"  # Invalid
        elif edge_case == "ip_like":
            return "192.168.1.1"  # Looks like IP but valid bucket name
        elif edge_case == "special_chars":
            return "my_bucket$invalid"  # Invalid chars
        else:
            # Normal bucket name
            prefix = random.choice(["my", "test", "prod", "dev", "data"])
            suffix = random.choice(["bucket", "storage", "archive", "backup"])
            return f"{prefix}-{suffix}-{random.randint(1000, 9999)}"
    
    def generate_rds_instance(self, edge_case=None):
        """Generate RDS instance identifier"""
        if edge_case == "min_length":
            return "a"  # 1 char minimum
        elif edge_case == "max_length":
            return ''.join(random.choices(string.ascii_lowercase + string.digits + '-', k=63))
        elif edge_case == "uppercase":
            return "MyRDSInstance"  # Mixed case
        elif edge_case == "special_prefix":
            return "mysql-prod-01"
        else:
            engines = ["mysql", "postgres", "oracle", "sqlserver", "aurora"]
            env = ["prod", "dev", "test", "staging"]
            return f"{random.choice(engines)}-{random.choice(env)}-{random.randint(100, 999)}"
    
    def generate_private_ip(self, valid=True):
        """Generate private IP addresses"""
        if valid:
            # Private IP ranges
            ranges = [
                (10, 0, 0, 0, 10, 255, 255, 255),  # 10.0.0.0/8
                (172, 16, 0, 0, 172, 31, 255, 255),  # 172.16.0.0/12
                (192, 168, 0, 0, 192, 168, 255, 255),  # 192.168.0.0/16
            ]
            range_choice = random.choice(ranges)
            return f"{random.randint(range_choice[0], range_choice[4])}.{random.randint(range_choice[1], range_choice[5])}.{random.randint(range_choice[2], range_choice[6])}.{random.randint(range_choice[3], range_choice[7])}"
        else:
            # Public IPs that should not be masked
            return f"{random.randint(1, 9)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"
    
    def generate_iam_role(self):
        """Generate IAM role ARN"""
        account_id = ''.join(random.choices(string.digits, k=12))
        role_name = f"{''.join(random.choices(string.ascii_lowercase, k=10))}-role"
        return f"arn:aws:iam::{account_id}:role/{role_name}"
    
    def generate_security_group(self):
        """Generate security group ID"""
        return f"sg-{''.join(random.choices('0123456789abcdef', k=17))}"
    
    def generate_vpc_id(self):
        """Generate VPC ID"""
        return f"vpc-{''.join(random.choices('0123456789abcdef', k=17))}"
    
    def generate_lambda_function(self):
        """Generate Lambda function ARN"""
        region = random.choice(self.aws_regions)
        account_id = ''.join(random.choices(string.digits, k=12))
        func_name = f"{''.join(random.choices(string.ascii_lowercase, k=15))}-function"
        return f"arn:aws:lambda:{region}:{account_id}:function:{func_name}"
    
    def generate_edge_case_json(self, case_type):
        """Generate JSON with specific edge cases"""
        
        if case_type == "deeply_nested":
            # Create deeply nested structure
            result = {"level_0": {}}
            current = result["level_0"]
            for i in range(1, 100):
                current[f"level_{i}"] = {
                    "ec2_instance": self.generate_ec2_instance_id(),
                    "data": {}
                }
                current = current[f"level_{i}"]["data"]
            return result
            
        elif case_type == "massive_array":
            # Large array of resources
            return {
                "instances": [self.generate_ec2_instance_id() for _ in range(10000)],
                "buckets": [self.generate_s3_bucket_name() for _ in range(5000)],
                "private_ips": [self.generate_private_ip() for _ in range(5000)]
            }
            
        elif case_type == "mixed_valid_invalid":
            # Mix of valid and invalid resources
            return {
                "valid_instances": [self.generate_ec2_instance_id(valid=True) for _ in range(10)],
                "invalid_instances": [self.generate_ec2_instance_id(valid=False) for _ in range(10)],
                "edge_case_buckets": [
                    self.generate_s3_bucket_name("min_length"),
                    self.generate_s3_bucket_name("max_length"),
                    self.generate_s3_bucket_name("dots"),
                    self.generate_s3_bucket_name("ip_like"),
                ],
                "mixed_ips": [
                    self.generate_private_ip(valid=True),
                    self.generate_private_ip(valid=False),
                    "256.256.256.256",  # Invalid IP
                    "10.0.0.0.1",  # Invalid format
                ]
            }
            
        elif case_type == "unicode_content":
            # Unicode and special characters
            return {
                "description": "AWS resources with unicode: 你好世界 🌍 émojis",
                "instance": self.generate_ec2_instance_id(),
                "bucket": "my-bucket-世界",
                "tags": {
                    "Name": "Instance with émojis 🚀",
                    "Owner": "用户123"
                }
            }
            
        elif case_type == "boundary_values":
            # Test boundary conditions
            return {
                "min_values": {
                    "bucket": self.generate_s3_bucket_name("min_length"),
                    "rds": self.generate_rds_instance("min_length"),
                },
                "max_values": {
                    "bucket": self.generate_s3_bucket_name("max_length"),
                    "rds": self.generate_rds_instance("max_length"),
                },
                "edge_ips": [
                    "10.0.0.0",
                    "10.255.255.255",
                    "172.16.0.0",
                    "172.31.255.255",
                    "192.168.0.0",
                    "192.168.255.255",
                ]
            }
            
        elif case_type == "pattern_collision":
            # Resources that might cause pattern matching issues
            return {
                "similar_patterns": [
                    "i-1234567890abcdef0",  # EC2
                    "ami-1234567890abcdef0",  # AMI (not masked)
                    "eni-1234567890abcdef0",  # ENI (not masked)
                    "vol-1234567890abcdef0",  # Volume (not masked)
                ],
                "overlapping_text": "The instance i-1234567890abcdef0 is in vpc-1234567890abcdef0",
                "concatenated": "i-1234567890abcdef0i-0fedcba0987654321",  # Two IDs together
            }
            
        elif case_type == "performance_stress":
            # Large payload for performance testing
            instances = []
            text_parts = []
            
            for i in range(1000):
                instance_id = self.generate_ec2_instance_id()
                instances.append(instance_id)
                text_parts.append(f"Instance {instance_id} in {self.generate_vpc_id()} with IP {self.generate_private_ip()}")
            
            return {
                "metadata": {
                    "count": len(instances),
                    "generated_at": datetime.now().isoformat()
                },
                "resources": {
                    "instances": instances,
                    "security_groups": [self.generate_security_group() for _ in range(500)],
                    "vpcs": [self.generate_vpc_id() for _ in range(100)],
                },
                "description": " ".join(text_parts)
            }
    
    def generate_claude_request(self, content, stream=False):
        """Generate a Claude API request format"""
        return {
            "model": "claude-3-sonnet-20240229",
            "messages": [
                {
                    "role": "user",
                    "content": content if isinstance(content, str) else json.dumps(content)
                }
            ],
            "max_tokens": 4096,
            "stream": stream
        }
    
    def save_test_case(self, name, data):
        """Save test case to file"""
        filename = f"test-cases/generated/{name}.json"
        with open(filename, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Generated: {filename}")

def main():
    """Generate all test cases"""
    generator = TestDataGenerator()
    
    # Create directory for generated test cases
    import os
    os.makedirs("test-cases/generated", exist_ok=True)
    
    # Generate various edge cases
    test_cases = {
        "deeply_nested": generator.generate_edge_case_json("deeply_nested"),
        "massive_array": generator.generate_edge_case_json("massive_array"),
        "mixed_valid_invalid": generator.generate_edge_case_json("mixed_valid_invalid"),
        "unicode_content": generator.generate_edge_case_json("unicode_content"),
        "boundary_values": generator.generate_edge_case_json("boundary_values"),
        "pattern_collision": generator.generate_edge_case_json("pattern_collision"),
        "performance_stress": generator.generate_edge_case_json("performance_stress"),
    }
    
    # Save each test case
    for name, data in test_cases.items():
        # Save raw data
        generator.save_test_case(f"{name}_data", data)
        
        # Save as Claude request
        claude_request = generator.generate_claude_request(data)
        generator.save_test_case(f"{name}_request", claude_request)
    
    # Generate specific malformed JSON cases
    malformed_cases = [
        ('{"incomplete": "json"',  "incomplete_json"),
        ('{"key": "value", invalid}', "invalid_syntax"),
        ('{"nested": {"deep": {"deeper": ' * 200 + '}}' * 200, "too_deep"),
        ('{"huge_string": "' + 'x' * 10000000 + '"}', "huge_string"),
    ]
    
    for content, name in malformed_cases:
        with open(f"test-cases/generated/malformed_{name}.txt", 'w') as f:
            f.write(content)
        print(f"Generated: test-cases/generated/malformed_{name}.txt")
    
    print("\nTest data generation complete!")
    print(f"Generated {len(test_cases)} test cases + {len(malformed_cases)} malformed cases")

if __name__ == "__main__":
    main()