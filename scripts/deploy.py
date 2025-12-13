#!/usr/bin/env python3
"""
DDGo Deployment Script
Automates deployment to various environments.
Demonstrates Python scripting skills mentioned in job description.
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class DeploymentError(Exception):
    """Custom exception for deployment errors."""
    pass


class Deployer:
    """Handles deployment operations for DDGo."""

    VALID_ENVIRONMENTS = ['dev', 'staging', 'prod']
    PROJECT_ROOT = Path(__file__).parent.parent

    def __init__(self, environment: str, dry_run: bool = False):
        if environment not in self.VALID_ENVIRONMENTS:
            raise ValueError(f"Invalid environment: {environment}")

        self.environment = environment
        self.dry_run = dry_run
        self.start_time = datetime.utcnow()

    def run_command(
        self,
        cmd: list,
        cwd: Optional[Path] = None,
        capture: bool = False
    ) -> subprocess.CompletedProcess:
        """Execute a shell command."""
        logger.info(f"Running: {' '.join(cmd)}")

        if self.dry_run:
            logger.info("[DRY RUN] Command would be executed")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        try:
            result = subprocess.run(
                cmd,
                cwd=cwd or self.PROJECT_ROOT,
                capture_output=capture,
                text=True,
                check=True
            )
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed: {e.stderr}")
            raise DeploymentError(f"Command failed: {' '.join(cmd)}")

    def check_prerequisites(self) -> bool:
        """Verify all prerequisites are met."""
        logger.info("Checking prerequisites...")

        required_tools = ['docker', 'aws', 'terraform']
        missing = []

        for tool in required_tools:
            try:
                subprocess.run(
                    [tool, '--version'],
                    capture_output=True,
                    check=True
                )
            except (subprocess.CalledProcessError, FileNotFoundError):
                missing.append(tool)

        if missing:
            logger.error(f"Missing required tools: {', '.join(missing)}")
            return False

        # Check AWS credentials
        try:
            result = subprocess.run(
                ['aws', 'sts', 'get-caller-identity'],
                capture_output=True,
                text=True,
                check=True
            )
            identity = json.loads(result.stdout)
            logger.info(f"AWS Account: {identity['Account']}")
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            logger.error("AWS credentials not configured or invalid")
            return False

        logger.info("All prerequisites met")
        return True

    def build_image(self, tag: str) -> str:
        """Build Docker image."""
        logger.info(f"Building Docker image with tag: {tag}")

        image_name = f"ddgo-api:{tag}"

        cmd = [
            'docker', 'build',
            '-f', 'docker/Dockerfile',
            '-t', image_name,
            '--target', 'production',
            '.'
        ]

        self.run_command(cmd)
        logger.info(f"Image built: {image_name}")

        return image_name

    def push_to_ecr(self, image_name: str, ecr_repo: str) -> str:
        """Push image to ECR."""
        logger.info(f"Pushing {image_name} to ECR...")

        # Get ECR login
        result = self.run_command(
            ['aws', 'ecr', 'get-login-password', '--region', 'us-east-1'],
            capture=True
        )

        if not self.dry_run:
            # Login to ECR
            login_cmd = [
                'docker', 'login', '--username', 'AWS',
                '--password-stdin', ecr_repo.split('/')[0]
            ]
            subprocess.run(
                login_cmd,
                input=result.stdout,
                text=True,
                check=True
            )

        # Tag image
        ecr_image = f"{ecr_repo}:{image_name.split(':')[1]}"
        self.run_command(['docker', 'tag', image_name, ecr_image])

        # Push image
        self.run_command(['docker', 'push', ecr_image])

        logger.info(f"Image pushed: {ecr_image}")
        return ecr_image

    def deploy_terraform(self) -> dict:
        """Apply Terraform changes."""
        logger.info(f"Deploying Terraform for {self.environment}...")

        tf_dir = self.PROJECT_ROOT / 'terraform' / 'environments' / self.environment

        # Initialize
        self.run_command(['terraform', 'init'], cwd=tf_dir)

        # Plan
        self.run_command(
            ['terraform', 'plan', '-out=tfplan'],
            cwd=tf_dir
        )

        # Apply
        self.run_command(
            ['terraform', 'apply', '-auto-approve', 'tfplan'],
            cwd=tf_dir
        )

        # Get outputs
        result = self.run_command(
            ['terraform', 'output', '-json'],
            cwd=tf_dir,
            capture=True
        )

        if not self.dry_run:
            outputs = json.loads(result.stdout)
            return {k: v['value'] for k, v in outputs.items()}

        return {}

    def update_ecs_service(self, cluster: str, service: str, image: str) -> None:
        """Update ECS service with new image."""
        logger.info(f"Updating ECS service {service} in cluster {cluster}...")

        # Get current task definition
        result = self.run_command(
            [
                'aws', 'ecs', 'describe-services',
                '--cluster', cluster,
                '--services', service,
                '--query', 'services[0].taskDefinition',
                '--output', 'text'
            ],
            capture=True
        )

        if self.dry_run:
            logger.info("[DRY RUN] Would update task definition and service")
            return

        current_task_def = result.stdout.strip()
        logger.info(f"Current task definition: {current_task_def}")

        # Get task definition details
        result = self.run_command(
            [
                'aws', 'ecs', 'describe-task-definition',
                '--task-definition', current_task_def
            ],
            capture=True
        )

        task_def = json.loads(result.stdout)['taskDefinition']

        # Update container image
        for container in task_def['containerDefinitions']:
            if container['name'] == 'app':
                container['image'] = image

        # Register new task definition
        new_task_def = {
            'family': task_def['family'],
            'containerDefinitions': task_def['containerDefinitions'],
            'executionRoleArn': task_def['executionRoleArn'],
            'taskRoleArn': task_def.get('taskRoleArn', ''),
            'networkMode': task_def['networkMode'],
            'requiresCompatibilities': task_def['requiresCompatibilities'],
            'cpu': task_def['cpu'],
            'memory': task_def['memory'],
        }

        result = self.run_command(
            [
                'aws', 'ecs', 'register-task-definition',
                '--cli-input-json', json.dumps(new_task_def)
            ],
            capture=True
        )

        new_task_def_arn = json.loads(result.stdout)['taskDefinition']['taskDefinitionArn']
        logger.info(f"New task definition: {new_task_def_arn}")

        # Update service
        self.run_command([
            'aws', 'ecs', 'update-service',
            '--cluster', cluster,
            '--service', service,
            '--task-definition', new_task_def_arn
        ])

        logger.info("ECS service update initiated")

    def wait_for_deployment(self, cluster: str, service: str, timeout: int = 600) -> bool:
        """Wait for ECS deployment to complete."""
        logger.info(f"Waiting for deployment to complete (timeout: {timeout}s)...")

        if self.dry_run:
            logger.info("[DRY RUN] Would wait for deployment")
            return True

        start = time.time()

        while time.time() - start < timeout:
            result = self.run_command(
                [
                    'aws', 'ecs', 'describe-services',
                    '--cluster', cluster,
                    '--services', service
                ],
                capture=True
            )

            service_info = json.loads(result.stdout)['services'][0]
            deployments = service_info['deployments']

            if len(deployments) == 1 and deployments[0]['rolloutState'] == 'COMPLETED':
                logger.info("Deployment completed successfully")
                return True

            running = deployments[0].get('runningCount', 0)
            desired = deployments[0].get('desiredCount', 0)
            logger.info(f"Deployment in progress: {running}/{desired} tasks running")

            time.sleep(15)

        logger.error("Deployment timed out")
        return False

    def verify_deployment(self, url: str) -> bool:
        """Verify deployment is healthy."""
        logger.info(f"Verifying deployment at {url}...")

        if self.dry_run:
            logger.info("[DRY RUN] Would verify deployment")
            return True

        import urllib.request
        import urllib.error

        health_url = f"{url}/health"

        for attempt in range(5):
            try:
                with urllib.request.urlopen(health_url, timeout=10) as response:
                    if response.status == 200:
                        logger.info("Health check passed")
                        return True
            except urllib.error.URLError as e:
                logger.warning(f"Health check failed (attempt {attempt + 1}): {e}")
                time.sleep(10)

        logger.error("Health check failed after 5 attempts")
        return False

    def deploy(self, skip_build: bool = False, skip_terraform: bool = False) -> bool:
        """Execute full deployment."""
        logger.info(f"Starting deployment to {self.environment}")
        logger.info(f"Dry run: {self.dry_run}")

        try:
            # Check prerequisites
            if not self.check_prerequisites():
                return False

            # Deploy infrastructure if needed
            outputs = {}
            if not skip_terraform:
                outputs = self.deploy_terraform()

            # Build and push image
            if not skip_build:
                tag = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
                image = self.build_image(tag)

                ecr_repo = outputs.get('ecr_repository', f'ddgo-api')
                ecr_image = self.push_to_ecr(image, ecr_repo)
            else:
                ecr_image = 'nginx:alpine'  # Placeholder

            # Update ECS service
            cluster = outputs.get('ecs_cluster_name', f'ddgo-{self.environment}')
            service = outputs.get('ecs_service_name', f'ddgo-{self.environment}-app')
            self.update_ecs_service(cluster, service, ecr_image)

            # Wait for deployment
            if not self.wait_for_deployment(cluster, service):
                raise DeploymentError("Deployment failed to complete")

            # Verify deployment
            alb_dns = outputs.get('alb_dns_name', 'localhost')
            if not self.verify_deployment(f"http://{alb_dns}"):
                raise DeploymentError("Deployment verification failed")

            duration = (datetime.utcnow() - self.start_time).total_seconds()
            logger.info(f"Deployment completed successfully in {duration:.1f}s")
            return True

        except DeploymentError as e:
            logger.error(f"Deployment failed: {e}")
            return False
        except Exception as e:
            logger.exception(f"Unexpected error: {e}")
            return False


def main():
    parser = argparse.ArgumentParser(
        description='DDGo Deployment Script',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s dev                    Deploy to development
  %(prog)s staging --dry-run      Dry run for staging
  %(prog)s prod --skip-terraform  Skip infrastructure changes
        """
    )

    parser.add_argument(
        'environment',
        choices=['dev', 'staging', 'prod'],
        help='Target environment'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    parser.add_argument(
        '--skip-build',
        action='store_true',
        help='Skip building Docker image'
    )
    parser.add_argument(
        '--skip-terraform',
        action='store_true',
        help='Skip Terraform deployment'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Confirm production deployments
    if args.environment == 'prod' and not args.dry_run:
        response = input("You are about to deploy to PRODUCTION. Continue? [y/N] ")
        if response.lower() != 'y':
            logger.info("Deployment cancelled")
            sys.exit(0)

    deployer = Deployer(args.environment, dry_run=args.dry_run)
    success = deployer.deploy(
        skip_build=args.skip_build,
        skip_terraform=args.skip_terraform
    )

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
