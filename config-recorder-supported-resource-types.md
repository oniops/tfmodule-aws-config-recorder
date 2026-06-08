# AWS Config Recorder — Supported Resource Types Reference

> **출처**: AWS Config 공식 문서. 2026-05-22 동기화.
> - [Supported Resource Types for AWS Config](https://docs.aws.amazon.com/config/latest/developerguide/resource-config-reference.html)
> - [RecordingModeOverride API Reference](https://docs.aws.amazon.com/config/latest/APIReference/API_RecordingModeOverride.html)
> - [Recording AWS Resources with AWS Config](https://docs.aws.amazon.com/config/latest/developerguide/select-resources.html)
>
> AWS 가 신규 resource type 을 지속 추가하므로 본 문서는 주기적 동기화 필요. 권위 SSOT 는 항상 AWS 공식 문서.

---

## 1. INCLUSION vs EXCLUSION — 운영 부담 비교 (의견)

| 기준 | INCLUSION (`included_resource_types`) | EXCLUSION (`excluded_resource_types`) |
|---|---|---|
| **유지보수 트리거** | (a) 워크로드 팀의 신규 서비스 도입 시마다, (b) AWS 의 신규 리소스 타입 출시 시마다, (c) SecurityHub 신규 활성 표준 / 컨트롤이 평가 대상 추가 시마다 → 매번 inclusion list 갱신 PR | 명시 제외할 타입을 새로 식별했을 때만 — AWS 신규 리소스 타입은 자동으로 기록 면적에 포함 |
| **실패 모드** | 추가 누락 → **무감지 보안 갭** (해당 타입 리소스가 생성돼도 finding 발생 안 함, 감사 / 사고 시점에 발각) | 제외 누락 → **추가 비용** 만 발생 (over-recording 은 보안상 안전) |
| **워크로드 팀 자율성** | 신규 서비스 도입 전 보안팀과 사전 협의 강제 | 협업 없이 자율 도입 가능 |
| **SecurityHub Standards 정합성** | 미커버 타입은 `INSUFFICIENT_DATA` 평가 → false negative | 모든 컨트롤이 데이터 받아 평가 — finding gap 없음 |
| **REQUIRED_TAGS 베이스라인 정합성** | inclusion 외 타입의 태그 위반 미탐지 → 컴플라이언스 점수 인공 왜곡 | 모든 supported type 자동 평가 |
| **AWS 신규 서비스 대응** | 매 출시마다 보안팀 PR 필수 (연 수십 회) | 무대응 자동 커버 |

**판정** — 본 프로젝트의 워크로드 멤버 (SecurityHub Standards + REQUIRED_TAGS 베이스라인 적용) 컨텍스트에서는 **EXCLUSION 이 압도적으로 운영 부담이 작다.**

INCLUSION 이 정당화되는 경우는 좁다:
- **단일 목적 계정** (예: DNS-only, CDN-only) — inclusion list 가 자연스럽게 좁고 안정적.
- **보안 baseline 미적용 sandbox 계정** — 의도된 가시성 축소를 수용할 때.

**추천 적용** — `module/recorder` 의 `member` schema 에 `excluded_resource_types` 추가하여 `all_supported = true` 의 기본 면적은 유지하면서 비용 압박 타입만 선별 제외. 두 워크로드 (`prd-an2p`, `anprd-an2p`) 의 청구 라인 차집합 (예: `anprd` 에 없는 `AWS::CloudFront::*` 계열, `prd` 에 없는 `AWS::EKS::*` 계열) 을 후보로 검토.

---

## 2. 리소스 타입 선택 의사결정 가이드

EXCLUSION 후보 검토 시 4-게이트 순서로 평가:

1. **AWS 서비스 사용 여부** — 청구 라인 + Cost Explorer 검토. ⚠️ 단, **무료 서비스 (IAM, RAM, Resource Explorer, ACM 등) 는 청구되지 않지만 리소스가 존재** — 청구 부재 ≠ 사용 부재. IAM 은 모든 계정에 반드시 포함, KMS 도 보안 키 발급 시 존재.
2. **SecurityHub Standards / Config Rule scope 여부** — 활성 컨트롤이 본 타입을 평가하면 제외 금지. `aws securityhub describe-standards-controls --standards-subscription-arn <arn>` 으로 컨트롤별 평가 대상 확인.
3. **REQUIRED_TAGS / 베이스라인 룰 scope 여부** — 본 프로젝트 베이스라인은 모든 supported type 대상 — 제외 시 컴플라이언스 점수 인공 왜곡.
4. **변경 빈도 vs 보안 가치** — 고변동 + 저보안 → DAILY override 후보. 저변동 + 고보안 → CONTINUOUS 유지.

DAILY override 후보 검토 시:
- 본 타입이 `recording_mode_override` 의 `resourceTypes` Valid Values 에 포함되는지 § 3 표의 **DAILY** 열로 확인.
- DAILY override 는 **base `recording_frequency = CONTINUOUS`** 일 때만 적용 가능 (AWS API 제약).
- AWS Firewall Manager 사용 중인 환경은 CONTINUOUS 유지 권장 (AWS 공식 권고 — FM 이 실시간 변화 감지에 의존).

---

## 3. 지원 Resource Type 목록

**범례**:
- **DAILY 열**:
  - ✅ — `recording_mode_override` 에서 DAILY 로 override 가능
  - ❌ — `recording_mode_override` Valid Values 미포함 → base `recording_frequency` 만 적용 (per-type override 불가)
  - ⚠️ — DAILY 명시 금지 (AWS API reject — `AWS::Config::*` 내부 컴플라이언스 타입 한정)
- **Scope**: R (Regional) / G (Global — 단일 home region 에서만 기록 권장. `include_global_resource_types` 분기)

### 3.1 Compute (EC2 / EBS / EC2 Image Builder)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::EC2::CapacityReservation` | EC2 capacity reservation | R | ✅ |
| `AWS::EC2::CarrierGateway` | Wavelength carrier gateway | R | ✅ |
| `AWS::EC2::ClientVpnEndpoint` | Client VPN endpoint | R | ✅ |
| `AWS::EC2::CustomerGateway` | VPN customer gateway | R | ✅ |
| `AWS::EC2::DHCPOptions` | VPC DHCP options set | R | ✅ |
| `AWS::EC2::EC2Fleet` | EC2 fleet | R | ✅ |
| `AWS::EC2::EgressOnlyInternetGateway` | IPv6 egress-only IGW | R | ✅ |
| `AWS::EC2::EIP` | Elastic IP address | R | ✅ |
| `AWS::EC2::EIPAssociation` | EIP ↔ ENI / Instance 결합 | R | ❌ |
| `AWS::EC2::FlowLog` | VPC flow log | R | ✅ |
| `AWS::EC2::Host` | Dedicated Host | R | ✅ |
| `AWS::EC2::Instance` | EC2 instance | R | ✅ |
| `AWS::EC2::InstanceConnectEndpoint` | Instance Connect endpoint | R | ❌ |
| `AWS::EC2::InternetGateway` | Internet gateway | R | ✅ |
| `AWS::EC2::IPAM` | IPAM | R | ✅ |
| `AWS::EC2::IPAMPool` | IPAM pool | R | ✅ |
| `AWS::EC2::IPAMPoolCidr` | IPAM pool CIDR | R | ❌ |
| `AWS::EC2::IPAMResourceDiscovery` | IPAM resource discovery | R | ❌ |
| `AWS::EC2::IPAMResourceDiscoveryAssociation` | IPAM resource discovery association | R | ❌ |
| `AWS::EC2::IPAMScope` | IPAM scope | R | ✅ |
| `AWS::EC2::LaunchTemplate` | Launch template | R | ✅ |
| `AWS::EC2::NatGateway` | NAT gateway | R | ✅ |
| `AWS::EC2::NetworkAcl` | Network ACL | R | ✅ |
| `AWS::EC2::NetworkInsightsAccessScope` | Network Insights access scope | R | ✅ |
| `AWS::EC2::NetworkInsightsAccessScopeAnalysis` | Access scope analysis 결과 | R | ✅ |
| `AWS::EC2::NetworkInsightsAnalysis` | Network Insights analysis 결과 | R | ✅ |
| `AWS::EC2::NetworkInsightsPath` | Reachability path | R | ✅ |
| `AWS::EC2::NetworkInterface` | ENI | R | ✅ |
| `AWS::EC2::PrefixList` | Prefix list | R | ✅ |
| `AWS::EC2::RegisteredHAInstance` | HA 등록 인스턴스 | R | ✅ |
| `AWS::EC2::RouteTable` | Route table | R | ✅ |
| `AWS::EC2::SecurityGroup` | Security group | R | ✅ |
| `AWS::EC2::SecurityGroupVpcAssociation` | SG ↔ VPC 결합 | R | ❌ |
| `AWS::EC2::SnapshotBlockPublicAccess` | EBS snapshot public access block | R | ❌ |
| `AWS::EC2::SpotFleet` | Spot fleet | R | ✅ |
| `AWS::EC2::Subnet` | Subnet | R | ✅ |
| `AWS::EC2::SubnetCidrBlock` | Subnet CIDR block | R | ❌ |
| `AWS::EC2::SubnetNetworkAclAssociation` | Subnet ↔ NACL 결합 | R | ❌ |
| `AWS::EC2::SubnetRouteTableAssociation` | Subnet ↔ Route table 결합 | R | ✅ |
| `AWS::EC2::TrafficMirrorFilter` | Traffic mirror filter | R | ✅ |
| `AWS::EC2::TrafficMirrorSession` | Traffic mirror session | R | ✅ |
| `AWS::EC2::TrafficMirrorTarget` | Traffic mirror target | R | ✅ |
| `AWS::EC2::TransitGateway` | Transit Gateway | R | ✅ |
| `AWS::EC2::TransitGatewayAttachment` | TGW attachment | R | ✅ |
| `AWS::EC2::TransitGatewayConnect` | TGW Connect | R | ✅ |
| `AWS::EC2::TransitGatewayMulticastDomain` | TGW multicast domain | R | ✅ |
| `AWS::EC2::TransitGatewayRouteTable` | TGW route table | R | ✅ |
| `AWS::EC2::VerifiedAccessInstance` | Verified Access instance | R | ❌ |
| `AWS::EC2::Volume` | EBS volume | R | ✅ |
| `AWS::EC2::VPC` | VPC | R | ✅ |
| `AWS::EC2::VPCBlockPublicAccessExclusion` | VPC public access block 예외 | R | ❌ |
| `AWS::EC2::VPCBlockPublicAccessOptions` | VPC public access block 옵션 | R | ❌ |
| `AWS::EC2::VPCEndpoint` | VPC endpoint | R | ✅ |
| `AWS::EC2::VPCEndpointConnectionNotification` | VPC endpoint connection 알림 | R | ❌ |
| `AWS::EC2::VPCEndpointService` | VPC endpoint service | R | ✅ |
| `AWS::EC2::VPCGatewayAttachment` | VPC ↔ gateway 결합 | R | ❌ |
| `AWS::EC2::VPCPeeringConnection` | VPC peering | R | ✅ |
| `AWS::EC2::VPNConnection` | VPN connection | R | ✅ |
| `AWS::EC2::VPNConnectionRoute` | VPN connection route | R | ❌ |
| `AWS::EC2::VPNGateway` | VPN gateway | R | ✅ |
| `AWS::ImageBuilder::ContainerRecipe` | Image Builder container recipe | R | ✅ |
| `AWS::ImageBuilder::DistributionConfiguration` | Distribution configuration | R | ✅ |
| `AWS::ImageBuilder::ImagePipeline` | Image pipeline | R | ✅ |
| `AWS::ImageBuilder::ImageRecipe` | Image recipe | R | ✅ |
| `AWS::ImageBuilder::InfrastructureConfiguration` | Infrastructure configuration | R | ✅ |
| `AWS::ImageBuilder::LifecyclePolicy` | Lifecycle policy | R | ❌ |

### 3.2 Containers (ECR / ECS / EKS / EFS)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::ECR::PublicRepository` | ECR public repository | R | ✅ |
| `AWS::ECR::PullThroughCacheRule` | Pull through cache rule | R | ✅ |
| `AWS::ECR::RegistryPolicy` | Registry policy | R | ✅ |
| `AWS::ECR::ReplicationConfiguration` | Replication config | R | ❌ |
| `AWS::ECR::Repository` | ECR repository | R | ✅ |
| `AWS::ECR::RepositoryCreationTemplate` | Repository creation template | R | ❌ |
| `AWS::ECS::CapacityProvider` | ECS capacity provider | R | ✅ |
| `AWS::ECS::Cluster` | ECS cluster | R | ✅ |
| `AWS::ECS::Service` | ECS service | R | ✅ |
| `AWS::ECS::TaskDefinition` | ECS task definition | R | ✅ |
| `AWS::ECS::TaskSet` | ECS task set | R | ✅ |
| `AWS::EKS::Addon` | EKS add-on | R | ✅ |
| `AWS::EKS::Cluster` | EKS cluster | R | ✅ |
| `AWS::EKS::FargateProfile` | EKS Fargate profile | R | ✅ |
| `AWS::EKS::IdentityProviderConfig` | EKS IdP config | R | ✅ |
| `AWS::EKS::Nodegroup` | EKS node group | R | ❌ |
| `AWS::EFS::AccessPoint` | EFS access point | R | ✅ |
| `AWS::EFS::FileSystem` | EFS file system | R | ✅ |

### 3.3 Storage (S3 / Backup)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::S3::AccessGrant` | S3 Access Grant | R | ❌ |
| `AWS::S3::AccessGrantsInstance` | Access Grants instance | R | ❌ |
| `AWS::S3::AccessGrantsLocation` | Access Grants location | R | ❌ |
| `AWS::S3::AccessPoint` | S3 access point | R | ✅ |
| `AWS::S3::AccountPublicAccessBlock` | 계정 수준 public access block | R | ✅ |
| `AWS::S3::Bucket` | S3 bucket | R | ✅ |
| `AWS::S3::BucketPolicy` | S3 bucket policy | R | ❌ |
| `AWS::S3::MultiRegionAccessPoint` | Multi-region access point | R | ✅ |
| `AWS::S3::StorageLens` | Storage Lens | R | ✅ |
| `AWS::S3::StorageLensGroup` | Storage Lens group | R | ❌ |
| `AWS::S3Express::BucketPolicy` | S3 Express bucket policy | R | ❌ |
| `AWS::S3Express::DirectoryBucket` | S3 Express directory bucket | R | ❌ |
| `AWS::S3Tables::TableBucket` | S3 Tables bucket | R | ❌ |
| `AWS::S3Tables::TableBucketPolicy` | S3 Tables bucket policy | R | ❌ |
| `AWS::Backup::BackupPlan` | Backup plan | R | ✅ |
| `AWS::Backup::BackupSelection` | Backup selection | R | ✅ |
| `AWS::Backup::BackupVault` | Backup vault | R | ✅ |
| `AWS::Backup::RecoveryPoint` | Backup recovery point | R | ✅ |
| `AWS::Backup::ReportPlan` | Backup report plan | R | ✅ |
| `AWS::Backup::RestoreTestingPlan` | Backup restore testing plan | R | ❌ |
| `AWS::BackupGateway::Hypervisor` | Backup Gateway hypervisor | R | ❌ |

### 3.4 Database (RDS / Redshift / DynamoDB / Others)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::RDS::DBCluster` | RDS Aurora cluster | R | ✅ |
| `AWS::RDS::DBClusterSnapshot` | Aurora cluster snapshot | R | ✅ |
| `AWS::RDS::DBInstance` | RDS DB instance | R | ✅ |
| `AWS::RDS::DBSecurityGroup` | RDS DB security group | R | ✅ |
| `AWS::RDS::DBSnapshot` | RDS DB snapshot | R | ✅ |
| `AWS::RDS::DBSubnetGroup` | RDS DB subnet group | R | ✅ |
| `AWS::RDS::EventSubscription` | RDS event subscription | R | ✅ |
| `AWS::RDS::GlobalCluster` | Aurora global cluster | G | ✅ |
| `AWS::RDS::Integration` | RDS integration | R | ❌ |
| `AWS::RDS::OptionGroup` | RDS option group | R | ✅ |
| `AWS::Redshift::Cluster` | Redshift cluster | R | ✅ |
| `AWS::Redshift::ClusterParameterGroup` | Cluster parameter group | R | ✅ |
| `AWS::Redshift::ClusterSecurityGroup` | Cluster security group | R | ✅ |
| `AWS::Redshift::ClusterSnapshot` | Cluster snapshot | R | ✅ |
| `AWS::Redshift::ClusterSubnetGroup` | Cluster subnet group | R | ✅ |
| `AWS::Redshift::EndpointAccess` | Endpoint access | R | ✅ |
| `AWS::Redshift::EndpointAuthorization` | Endpoint authorization | R | ❌ |
| `AWS::Redshift::EventSubscription` | Event subscription | R | ✅ |
| `AWS::Redshift::Integration` | Redshift integration | R | ❌ |
| `AWS::Redshift::ScheduledAction` | Scheduled action | R | ✅ |
| `AWS::DynamoDB::Table` | DynamoDB table | R | ✅ |
| `AWS::MemoryDB::SubnetGroup` | MemoryDB subnet group | R | ❌ |
| `AWS::Cassandra::Keyspace` | Keyspaces (Cassandra) keyspace | R | ✅ |
| `AWS::QLDB::Ledger` | QLDB ledger | R | ✅ |
| `AWS::DSQL::Cluster` | Aurora DSQL cluster | R | ❌ |

### 3.5 Networking (ELB / Route 53 / Network Firewall / Global Accelerator / Network Manager)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::ElasticLoadBalancing::LoadBalancer` | Classic Load Balancer | R | ✅ |
| `AWS::ElasticLoadBalancingV2::LoadBalancer` | ALB / NLB / GWLB | R | ✅ |
| `AWS::ElasticLoadBalancingV2::Listener` | ELBv2 listener | R | ✅ |
| `AWS::CloudFront::Distribution` | CloudFront distribution | G | ✅ |
| `AWS::CloudFront::KeyValueStore` | CloudFront KV store | G | ❌ |
| `AWS::CloudFront::PublicKey` | Field-level encryption public key | G | ❌ |
| `AWS::CloudFront::RealtimeLogConfig` | Real-time log config | G | ❌ |
| `AWS::CloudFront::StreamingDistribution` | RTMP streaming distribution | G | ✅ |
| `AWS::Route53::DNSSEC` | Route 53 DNSSEC | G | ❌ |
| `AWS::Route53::HealthCheck` | Route 53 health check | G | ❌ |
| `AWS::Route53::HostedZone` | Route 53 hosted zone | G | ✅ |
| `AWS::Route53Profiles::Profile` | Route 53 profile | R | ❌ |
| `AWS::Route53Profiles::ProfileAssociation` | Route 53 profile association | R | ❌ |
| `AWS::Route53Resolver::FirewallDomainList` | DNS Firewall domain list | R | ✅ |
| `AWS::Route53Resolver::FirewallRuleGroup` | DNS Firewall rule group | R | ✅ |
| `AWS::Route53Resolver::FirewallRuleGroupAssociation` | DNS Firewall rule group 결합 | R | ✅ |
| `AWS::Route53Resolver::ResolverEndpoint` | Resolver endpoint | R | ✅ |
| `AWS::Route53Resolver::ResolverQueryLoggingConfig` | Query logging config | R | ✅ |
| `AWS::Route53Resolver::ResolverQueryLoggingConfigAssociation` | Query logging 결합 | R | ✅ |
| `AWS::Route53Resolver::ResolverRule` | Resolver rule | R | ✅ |
| `AWS::Route53Resolver::ResolverRuleAssociation` | Resolver rule 결합 | R | ✅ |
| `AWS::NetworkFirewall::Firewall` | Network Firewall | R | ✅ |
| `AWS::NetworkFirewall::FirewallPolicy` | Network Firewall policy | R | ✅ |
| `AWS::NetworkFirewall::RuleGroup` | Network Firewall rule group | R | ✅ |
| `AWS::NetworkFirewall::TLSInspectionConfiguration` | TLS inspection config | R | ❌ |
| `AWS::NetworkFirewall::VpcEndpointAssociation` | VPC endpoint association | R | ❌ |
| `AWS::GlobalAccelerator::Accelerator` | Global Accelerator accelerator | G | ✅ |
| `AWS::GlobalAccelerator::EndpointGroup` | Endpoint group | G | ✅ |
| `AWS::GlobalAccelerator::Listener` | Listener | G | ✅ |
| `AWS::NetworkManager::ConnectPeer` | Cloud WAN Connect peer | G | ✅ |
| `AWS::NetworkManager::CustomerGatewayAssociation` | Customer gateway 결합 | G | ✅ |
| `AWS::NetworkManager::Device` | Network Manager device | G | ✅ |
| `AWS::NetworkManager::GlobalNetwork` | Global network | G | ✅ |
| `AWS::NetworkManager::Link` | Network Manager link | G | ✅ |
| `AWS::NetworkManager::LinkAssociation` | Link association | G | ✅ |
| `AWS::NetworkManager::Site` | Network Manager site | G | ✅ |
| `AWS::NetworkManager::TransitGatewayPeering` | TGW peering | G | ❌ |
| `AWS::NetworkManager::TransitGatewayRegistration` | TGW registration | G | ✅ |
| `AWS::ARCZonalShift::AutoshiftObserverNotificationStatus` | ARC zonal shift autoshift 상태 | G | ❌ |
| `AWS::Route53RecoveryControl::Cluster` | ARC routing control cluster | G | ✅ |
| `AWS::Route53RecoveryControl::ControlPanel` | ARC control panel | G | ✅ |
| `AWS::Route53RecoveryControl::RoutingControl` | ARC routing control | G | ✅ |
| `AWS::Route53RecoveryControl::SafetyRule` | ARC safety rule | G | ✅ |
| `AWS::Route53RecoveryReadiness::Cell` | ARC readiness cell | G | ✅ |
| `AWS::Route53RecoveryReadiness::ReadinessCheck` | ARC readiness check | G | ✅ |
| `AWS::Route53RecoveryReadiness::RecoveryGroup` | ARC recovery group | G | ✅ |
| `AWS::Route53RecoveryReadiness::ResourceSet` | ARC resource set | G | ✅ |

### 3.6 Identity & Security (IAM / KMS / ACM / Secrets Manager / Cognito / Inspector / GuardDuty / Macie / Detective / Access Analyzer / Audit Manager / WAF / Shield / Firewall Manager)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::IAM::Group` | IAM group | G | ✅ |
| `AWS::IAM::GroupPolicy` | IAM group inline policy | G | ❌ |
| `AWS::IAM::InstanceProfile` | IAM instance profile | G | ✅ |
| `AWS::IAM::OIDCProvider` | IAM OIDC provider | G | ❌ |
| `AWS::IAM::Policy` | IAM customer managed policy | G | ✅ |
| `AWS::IAM::Role` | IAM role | G | ✅ |
| `AWS::IAM::RolePolicy` | IAM role inline policy | G | ❌ |
| `AWS::IAM::SAMLProvider` | IAM SAML provider | G | ✅ |
| `AWS::IAM::ServerCertificate` | IAM server certificate | G | ✅ |
| `AWS::IAM::User` | IAM user | G | ✅ |
| `AWS::IAM::UserPolicy` | IAM user inline policy | G | ❌ |
| `AWS::AccessAnalyzer::Analyzer` | IAM Access Analyzer | R | ✅ |
| `AWS::RolesAnywhere::CRL` | Roles Anywhere CRL | R | ❌ |
| `AWS::RolesAnywhere::Profile` | Roles Anywhere profile | R | ❌ |
| `AWS::RolesAnywhere::TrustAnchor` | Roles Anywhere trust anchor | R | ❌ |
| `AWS::KMS::Alias` | KMS alias | R | ✅ |
| `AWS::KMS::Key` | KMS key | R | ✅ |
| `AWS::ACM::Certificate` | ACM certificate | R | ✅ |
| `AWS::ACMPCA::CertificateAuthority` | Private CA authority | R | ✅ |
| `AWS::ACMPCA::CertificateAuthorityActivation` | Private CA activation | R | ✅ |
| `AWS::PCAConnectorAD::Connector` | Private CA AD connector | R | ❌ |
| `AWS::PCAConnectorAD::DirectoryRegistration` | Private CA AD directory | R | ❌ |
| `AWS::PCAConnectorAD::Template` | Private CA AD template | R | ❌ |
| `AWS::PCAConnectorSCEP::Challenge` | Private CA SCEP challenge | R | ❌ |
| `AWS::PCAConnectorSCEP::Connector` | Private CA SCEP connector | R | ❌ |
| `AWS::SecretsManager::Secret` | Secrets Manager secret | R | ✅ |
| `AWS::Cognito::IdentityPool` | Cognito identity pool | R | ❌ |
| `AWS::Cognito::IdentityPoolRoleAttachment` | Identity pool role mapping | R | ❌ |
| `AWS::Cognito::LogDeliveryConfiguration` | Log delivery config | R | ❌ |
| `AWS::Cognito::UserPool` | Cognito user pool | R | ✅ |
| `AWS::Cognito::UserPoolClient` | User pool client | R | ✅ |
| `AWS::Cognito::UserPoolDomain` | User pool domain | R | ❌ |
| `AWS::Cognito::UserPoolGroup` | User pool group | R | ✅ |
| `AWS::Cognito::UserPoolIdentityProvider` | User pool IdP | R | ❌ |
| `AWS::Cognito::UserPoolResourceServer` | User pool resource server | R | ❌ |
| `AWS::Cognito::UserPoolUICustomizationAttachment` | User pool UI customization | R | ❌ |
| `AWS::VerifiedPermissions::IdentitySource` | Verified Permissions identity source | R | ❌ |
| `AWS::GuardDuty::Detector` | GuardDuty detector | R | ✅ |
| `AWS::GuardDuty::Filter` | GuardDuty filter | R | ✅ |
| `AWS::GuardDuty::IPSet` | GuardDuty IP set | R | ✅ |
| `AWS::GuardDuty::MalwareProtectionPlan` | Malware protection plan | R | ❌ |
| `AWS::GuardDuty::ThreatIntelSet` | Threat intelligence set | R | ✅ |
| `AWS::InspectorV2::Activation` | Inspector activation 상태 | R | ❌ |
| `AWS::InspectorV2::Filter` | Inspector filter | R | ✅ |
| `AWS::Macie::Session` | Macie session | R | ❌ |
| `AWS::Detective::Graph` | Detective graph | R | ✅ |
| `AWS::Detective::OrganizationAdmin` | Detective org admin | R | ❌ |
| `AWS::AuditManager::Assessment` | Audit Manager assessment | R | ✅ |
| `AWS::WAF::RateBasedRule` | Classic WAF rate-based rule | G | ✅ |
| `AWS::WAF::Rule` | Classic WAF rule | G | ✅ |
| `AWS::WAF::RuleGroup` | Classic WAF rule group | G | ✅ |
| `AWS::WAF::WebACL` | Classic WAF web ACL | G | ✅ |
| `AWS::WAFRegional::RateBasedRule` | WAF Regional rate-based rule | R | ✅ |
| `AWS::WAFRegional::Rule` | WAF Regional rule | R | ✅ |
| `AWS::WAFRegional::RuleGroup` | WAF Regional rule group | R | ✅ |
| `AWS::WAFRegional::WebACL` | WAF Regional web ACL | R | ✅ |
| `AWS::WAFv2::IPSet` | WAFv2 IP set | R | ✅ |
| `AWS::WAFv2::ManagedRuleSet` | WAFv2 managed rule set | R | ✅ |
| `AWS::WAFv2::RegexPatternSet` | WAFv2 regex pattern set | R | ✅ |
| `AWS::WAFv2::RuleGroup` | WAFv2 rule group | R | ✅ |
| `AWS::WAFv2::WebACL` | WAFv2 web ACL | R | ✅ |
| `AWS::Shield::Protection` | Shield Advanced protection | G | ✅ |
| `AWS::ShieldRegional::Protection` | Shield Regional protection | R | ✅ |
| `AWS::XRay::EncryptionConfig` | X-Ray encryption config | R | ✅ |

### 3.7 Compute Workloads (Lambda / Auto Scaling / Batch / Elastic Beanstalk / App Runner / App Mesh / Amplify)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::Lambda::CodeSigningConfig` | Lambda code signing config | R | ✅ |
| `AWS::Lambda::Function` | Lambda function | R | ✅ |
| `AWS::AutoScaling::AutoScalingGroup` | Auto Scaling group | R | ✅ |
| `AWS::AutoScaling::LaunchConfiguration` | Launch configuration | R | ✅ |
| `AWS::AutoScaling::ScalingPolicy` | Scaling policy | R | ✅ |
| `AWS::AutoScaling::ScheduledAction` | Scheduled action | R | ✅ |
| `AWS::AutoScaling::WarmPool` | Auto Scaling warm pool | R | ✅ |
| `AWS::Batch::ComputeEnvironment` | Batch compute environment | R | ✅ |
| `AWS::Batch::ConsumableResource` | Batch consumable resource | R | ❌ |
| `AWS::Batch::JobQueue` | Batch job queue | R | ✅ |
| `AWS::Batch::SchedulingPolicy` | Batch scheduling policy | R | ✅ |
| `AWS::ElasticBeanstalk::Application` | Elastic Beanstalk application | R | ✅ |
| `AWS::ElasticBeanstalk::ApplicationVersion` | Elastic Beanstalk version | R | ✅ |
| `AWS::ElasticBeanstalk::Environment` | Elastic Beanstalk environment | R | ✅ |
| `AWS::AppRunner::Service` | App Runner service | R | ✅ |
| `AWS::AppRunner::VpcConnector` | App Runner VPC connector | R | ✅ |
| `AWS::AppMesh::GatewayRoute` | App Mesh gateway route | R | ✅ |
| `AWS::AppMesh::Mesh` | App Mesh mesh | R | ✅ |
| `AWS::AppMesh::Route` | App Mesh route | R | ✅ |
| `AWS::AppMesh::VirtualGateway` | App Mesh virtual gateway | R | ✅ |
| `AWS::AppMesh::VirtualNode` | App Mesh virtual node | R | ✅ |
| `AWS::AppMesh::VirtualRouter` | App Mesh virtual router | R | ✅ |
| `AWS::AppMesh::VirtualService` | App Mesh virtual service | R | ✅ |
| `AWS::Amplify::App` | Amplify app | R | ✅ |
| `AWS::Amplify::Branch` | Amplify branch | R | ✅ |

### 3.8 Application Integration (API Gateway / EventBridge / SNS / SQS / Step Functions / MQ / AppFlow / AppSync / AppConfig)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::ApiGateway::DomainName` | API Gateway custom domain | R | ❌ |
| `AWS::ApiGateway::Method` | API Gateway method | R | ❌ |
| `AWS::ApiGateway::RestApi` | API Gateway REST API | R | ✅ |
| `AWS::ApiGateway::Stage` | API Gateway stage | R | ✅ |
| `AWS::ApiGateway::UsagePlan` | API Gateway usage plan | R | ❌ |
| `AWS::ApiGatewayV2::Api` | API Gateway V2 API | R | ✅ |
| `AWS::ApiGatewayV2::Integration` | API Gateway V2 integration | R | ❌ |
| `AWS::ApiGatewayV2::Stage` | API Gateway V2 stage | R | ✅ |
| `AWS::Events::ApiDestination` | EventBridge API destination | R | ✅ |
| `AWS::Events::Archive` | EventBridge archive | R | ✅ |
| `AWS::Events::Connection` | EventBridge connection | R | ✅ |
| `AWS::Events::Endpoint` | EventBridge endpoint | R | ✅ |
| `AWS::Events::EventBus` | EventBridge event bus | R | ✅ |
| `AWS::Events::Rule` | EventBridge rule | R | ✅ |
| `AWS::EventSchemas::Discoverer` | Schema discoverer | R | ✅ |
| `AWS::EventSchemas::Registry` | Schema registry | R | ✅ |
| `AWS::EventSchemas::RegistryPolicy` | Schema registry policy | R | ✅ |
| `AWS::EventSchemas::Schema` | Schema | R | ✅ |
| `AWS::SNS::Topic` | SNS topic | R | ✅ |
| `AWS::SQS::Queue` | SQS queue | R | ✅ |
| `AWS::StepFunctions::Activity` | Step Functions activity | R | ✅ |
| `AWS::StepFunctions::StateMachine` | Step Functions state machine | R | ✅ |
| `AWS::AmazonMQ::Broker` | MQ broker | R | ✅ |
| `AWS::AppFlow::Flow` | AppFlow flow | R | ✅ |
| `AWS::AppIntegrations::Application` | AppIntegrations application | R | ❌ |
| `AWS::AppIntegrations::EventIntegration` | AppIntegrations event integration | R | ✅ |
| `AWS::AppSync::DataSource` | AppSync data source | R | ❌ |
| `AWS::AppSync::GraphQLApi` | AppSync GraphQL API | R | ✅ |
| `AWS::AppConfig::Application` | AppConfig application | R | ✅ |
| `AWS::AppConfig::ConfigurationProfile` | AppConfig configuration profile | R | ✅ |
| `AWS::AppConfig::DeploymentStrategy` | AppConfig deployment strategy | R | ✅ |
| `AWS::AppConfig::Environment` | AppConfig environment | R | ✅ |
| `AWS::AppConfig::Extension` | AppConfig extension | R | ❌ |
| `AWS::AppConfig::ExtensionAssociation` | AppConfig extension association | R | ❌ |
| `AWS::AppConfig::HostedConfigurationVersion` | AppConfig hosted config version | R | ✅ |

### 3.9 Analytics (Athena / Glue / EMR / Kinesis / MSK / OpenSearch / Redshift Analytics / QuickSight)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::Athena::DataCatalog` | Athena data catalog | R | ✅ |
| `AWS::Athena::PreparedStatement` | Athena prepared statement | R | ✅ |
| `AWS::Athena::WorkGroup` | Athena workgroup | R | ✅ |
| `AWS::Glue::Classifier` | Glue classifier | R | ✅ |
| `AWS::Glue::Crawler` | Glue crawler | R | ❌ |
| `AWS::Glue::Database` | Glue database | R | ❌ |
| `AWS::Glue::Job` | Glue job | R | ✅ |
| `AWS::Glue::MLTransform` | Glue ML transform | R | ✅ |
| `AWS::Glue::Registry` | Glue schema registry | R | ❌ |
| `AWS::DataBrew::Dataset` | DataBrew dataset | R | ❌ |
| `AWS::DataBrew::Job` | DataBrew job | R | ❌ |
| `AWS::DataBrew::Project` | DataBrew project | R | ❌ |
| `AWS::DataBrew::Recipe` | DataBrew recipe | R | ❌ |
| `AWS::DataBrew::Ruleset` | DataBrew ruleset | R | ❌ |
| `AWS::DataBrew::Schedule` | DataBrew schedule | R | ❌ |
| `AWS::EMR::SecurityConfiguration` | EMR security configuration | R | ✅ |
| `AWS::EMR::Studio` | EMR Studio | R | ❌ |
| `AWS::EMRContainers::VirtualCluster` | EMR Containers virtual cluster | R | ❌ |
| `AWS::EMRServerless::Application` | EMR Serverless application | R | ❌ |
| `AWS::Kinesis::ResourcePolicy` | Kinesis stream policy | R | ❌ |
| `AWS::Kinesis::Stream` | Kinesis stream | R | ✅ |
| `AWS::Kinesis::StreamConsumer` | Kinesis stream consumer | R | ✅ |
| `AWS::KinesisAnalyticsV2::Application` | Kinesis Analytics V2 application | R | ✅ |
| `AWS::KinesisFirehose::DeliveryStream` | Firehose delivery stream | R | ✅ |
| `AWS::KinesisVideo::SignalingChannel` | KVS signaling channel | R | ✅ |
| `AWS::KinesisVideo::Stream` | KVS stream | R | ✅ |
| `AWS::MSK::BatchScramSecret` | MSK SCRAM secret 결합 | R | ✅ |
| `AWS::MSK::Cluster` | MSK cluster | R | ✅ |
| `AWS::MSK::ClusterPolicy` | MSK cluster policy | R | ❌ |
| `AWS::MSK::Configuration` | MSK configuration | R | ✅ |
| `AWS::MSK::ServerlessCluster` | MSK serverless cluster | R | ❌ |
| `AWS::MSK::VpcConnection` | MSK VPC connection | R | ❌ |
| `AWS::KafkaConnect::Connector` | MSK Connect connector | R | ✅ |
| `AWS::KafkaConnect::CustomPlugin` | MSK Connect custom plugin | R | ❌ |
| `AWS::Elasticsearch::Domain` | OpenSearch (legacy ES) domain | R | ✅ |
| `AWS::OpenSearch::Domain` | OpenSearch domain | R | ✅ |
| `AWS::OpenSearchServerless::Collection` | OpenSearch Serverless collection | R | ❌ |
| `AWS::OpenSearchServerless::SecurityConfig` | OpenSearch Serverless security config | R | ❌ |
| `AWS::OpenSearchServerless::VpcEndpoint` | OpenSearch Serverless VPC endpoint | R | ❌ |
| `AWS::QuickSight::Dashboard` | QuickSight dashboard | R | ❌ |
| `AWS::QuickSight::Dataset` | QuickSight dataset | R | ❌ |
| `AWS::QuickSight::DataSource` | QuickSight data source | R | ✅ |
| `AWS::QuickSight::Template` | QuickSight template | R | ✅ |
| `AWS::QuickSight::Theme` | QuickSight theme | R | ✅ |
| `AWS::Kendra::Index` | Kendra index | R | ✅ |
| `AWS::CleanRooms::AnalysisTemplate` | Clean Rooms analysis template | R | ❌ |
| `AWS::CleanRooms::Collaboration` | Clean Rooms collaboration | R | ❌ |
| `AWS::CleanRooms::ConfiguredTable` | Clean Rooms configured table | R | ❌ |
| `AWS::CleanRooms::Membership` | Clean Rooms membership | R | ❌ |
| `AWS::CleanRooms::PrivacyBudgetTemplate` | Clean Rooms privacy budget template | R | ❌ |
| `AWS::CleanRoomsML::TrainingDataset` | Clean Rooms ML training dataset | R | ❌ |

### 3.10 Machine Learning & AI (SageMaker / Bedrock / Forecast / Personalize / Comprehend / Lex / Lookout / FraudDetector / HealthLake / Omics / Q Business)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::SageMaker::AppImageConfig` | SageMaker app image config | R | ✅ |
| `AWS::SageMaker::CodeRepository` | SageMaker code repo | R | ✅ |
| `AWS::SageMaker::DataQualityJobDefinition` | Data quality monitoring job | R | ❌ |
| `AWS::SageMaker::Domain` | SageMaker domain | R | ✅ |
| `AWS::SageMaker::EndpointConfig` | Endpoint config | R | ❌ |
| `AWS::SageMaker::FeatureGroup` | Feature group | R | ✅ |
| `AWS::SageMaker::Image` | SageMaker image | R | ✅ |
| `AWS::SageMaker::InferenceExperiment` | Inference experiment | R | ❌ |
| `AWS::SageMaker::MlflowTrackingServer` | MLflow tracking server | R | ❌ |
| `AWS::SageMaker::Model` | SageMaker model | R | ✅ |
| `AWS::SageMaker::ModelBiasJobDefinition` | Model bias monitoring | R | ❌ |
| `AWS::SageMaker::ModelExplainabilityJobDefinition` | Model explainability monitoring | R | ❌ |
| `AWS::SageMaker::ModelQualityJobDefinition` | Model quality monitoring | R | ❌ |
| `AWS::SageMaker::MonitoringSchedule` | Monitoring schedule | R | ❌ |
| `AWS::SageMaker::NotebookInstance` | Notebook instance | R | ❌ |
| `AWS::SageMaker::NotebookInstanceLifecycleConfig` | Notebook lifecycle config | R | ✅ |
| `AWS::SageMaker::StudioLifecycleConfig` | Studio lifecycle config | R | ❌ |
| `AWS::SageMaker::UserProfile` | SageMaker user profile | R | ❌ |
| `AWS::SageMaker::Workteam` | Workforce team | R | ✅ |
| `AWS::Bedrock::ApplicationInferenceProfile` | Bedrock inference profile | R | ❌ |
| `AWS::Bedrock::DataSource` | Bedrock knowledge base data source | R | ❌ |
| `AWS::Bedrock::Guardrail` | Bedrock guardrail | R | ❌ |
| `AWS::Bedrock::KnowledgeBase` | Bedrock knowledge base | R | ❌ |
| `AWS::Bedrock::Prompt` | Bedrock prompt template | R | ❌ |
| `AWS::BedrockAgentCore::BrowserCustom` | Bedrock agent browser tool | R | ❌ |
| `AWS::BedrockAgentCore::CodeInterpreterCustom` | Bedrock agent code interpreter | R | ❌ |
| `AWS::BedrockAgentCore::Gateway` | Bedrock agent gateway | R | ❌ |
| `AWS::BedrockAgentCore::Memory` | Bedrock agent memory | R | ❌ |
| `AWS::BedrockAgentCore::Runtime` | Bedrock agent runtime | R | ❌ |
| `AWS::BedrockAgentCore::WorkloadIdentity` | Bedrock agent workload identity | R | ❌ |
| `AWS::Forecast::Dataset` | Forecast dataset | R | ✅ |
| `AWS::Forecast::DatasetGroup` | Forecast dataset group | R | ✅ |
| `AWS::Personalize::Dataset` | Personalize dataset | R | ✅ |
| `AWS::Personalize::DatasetGroup` | Personalize dataset group | R | ✅ |
| `AWS::Personalize::Schema` | Personalize schema | R | ✅ |
| `AWS::Personalize::Solution` | Personalize solution | R | ✅ |
| `AWS::Comprehend::Flywheel` | Comprehend flywheel | R | ❌ |
| `AWS::Lex::Bot` | Lex bot | R | ✅ |
| `AWS::Lex::BotAlias` | Lex bot alias | R | ✅ |
| `AWS::LookoutMetrics::Alert` | Lookout for Metrics alert | R | ✅ |
| `AWS::LookoutVision::Project` | Lookout for Vision project | R | ✅ |
| `AWS::FraudDetector::EntityType` | Fraud Detector entity type | R | ✅ |
| `AWS::FraudDetector::Label` | Fraud Detector label | R | ✅ |
| `AWS::FraudDetector::Outcome` | Fraud Detector outcome | R | ✅ |
| `AWS::FraudDetector::Variable` | Fraud Detector variable | R | ✅ |
| `AWS::HealthLake::FHIRDatastore` | HealthLake FHIR datastore | R | ✅ |
| `AWS::Omics::ReferenceStore` | HealthOmics reference store | R | ❌ |
| `AWS::QBusiness::Application` | Q Business application | R | ❌ |
| `AWS::EntityResolution::IdMappingWorkflow` | Entity Resolution ID mapping | R | ❌ |
| `AWS::EntityResolution::MatchingWorkflow` | Entity Resolution matching | R | ❌ |
| `AWS::EntityResolution::SchemaMapping` | Entity Resolution schema mapping | R | ❌ |

### 3.11 Developer Tools (CodeBuild / CodeDeploy / CodePipeline / CodeArtifact / CodeGuru / Cloud9 / Device Farm)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::CodeBuild::Project` | CodeBuild project | R | ✅ |
| `AWS::CodeBuild::ReportGroup` | CodeBuild report group | R | ✅ |
| `AWS::CodeDeploy::Application` | CodeDeploy application | R | ✅ |
| `AWS::CodeDeploy::DeploymentConfig` | Deployment config | R | ✅ |
| `AWS::CodeDeploy::DeploymentGroup` | Deployment group | R | ✅ |
| `AWS::CodePipeline::Pipeline` | CodePipeline pipeline | R | ✅ |
| `AWS::CodeArtifact::Domain` | CodeArtifact domain | R | ❌ |
| `AWS::CodeArtifact::PackageGroup` | CodeArtifact package group | R | ❌ |
| `AWS::CodeArtifact::Repository` | CodeArtifact repository | R | ✅ |
| `AWS::CodeGuruProfiler::ProfilingGroup` | CodeGuru profiling group | R | ✅ |
| `AWS::CodeGuruReviewer::RepositoryAssociation` | CodeGuru repo association | R | ✅ |
| `AWS::Cloud9::EnvironmentEC2` | Cloud9 environment | R | ✅ |
| `AWS::DeviceFarm::InstanceProfile` | Device Farm instance profile | R | ✅ |
| `AWS::DeviceFarm::Project` | Device Farm project | R | ✅ |
| `AWS::DeviceFarm::TestGridProject` | Device Farm test grid | R | ✅ |
| `AWS::Signer::SigningProfile` | Signer signing profile | R | ✅ |
| `AWS::B2BI::Capability` | B2B Data Interchange capability | R | ❌ |
| `AWS::B2BI::Transformer` | B2B Data Interchange transformer | R | ❌ |

### 3.12 Management & Governance (CloudFormation / CloudTrail / CloudWatch / Config / SSM / Organizations / Service Catalog / Resource Explorer / RAM / Health / Billing)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::CloudFormation::GuardHook` | CFN Guard hook | R | ❌ |
| `AWS::CloudFormation::LambdaHook` | CFN Lambda hook | R | ❌ |
| `AWS::CloudFormation::Stack` | CloudFormation stack | R | ✅ |
| `AWS::CloudFormation::StackSet` | CloudFormation stack set | R | ❌ |
| `AWS::CloudTrail::EventDataStore` | CloudTrail event data store | R | ❌ |
| `AWS::CloudTrail::Trail` | CloudTrail trail | R | ✅ |
| `AWS::CloudWatch::Alarm` | CloudWatch alarm | R | ✅ |
| `AWS::CloudWatch::MetricStream` | CloudWatch metric stream | R | ✅ |
| `AWS::ApplicationSignals::ServiceLevelObjective` | Application Signals SLO | R | ❌ |
| `AWS::InternetMonitor::Monitor` | Internet Monitor | R | ❌ |
| `AWS::Logs::Destination` | CloudWatch Logs destination | R | ✅ |
| `AWS::RUM::AppMonitor` | CloudWatch RUM | R | ✅ |
| `AWS::Evidently::Launch` | Evidently launch | R | ✅ |
| `AWS::Evidently::Project` | Evidently project | R | ✅ |
| `AWS::Evidently::Segment` | Evidently segment | R | ❌ |
| `AWS::Config::AggregationAuthorization` | Config aggregation authorization | R | ❌ |
| `AWS::Config::ConfigurationRecorder` | **Config recorder (자기 자신)** | R | ⚠️ |
| `AWS::Config::ConformancePack` | Conformance pack | R | ❌ |
| `AWS::Config::ConformancePackCompliance` | **Conformance pack 컴플라이언스 결과** | R | ⚠️ |
| `AWS::Config::ResourceCompliance` | **리소스 컴플라이언스 결과** | R | ⚠️ |
| `AWS::Config::StoredQuery` | Config stored query | R | ❌ |
| `AWS::SSM::AssociationCompliance` | SSM association compliance | R | ✅ |
| `AWS::SSM::Document` | SSM document | R | ✅ |
| `AWS::SSM::FileData` | SSM file data | R | ✅ |
| `AWS::SSM::ManagedInstanceInventory` | SSM managed instance inventory | R | ✅ |
| `AWS::SSM::PatchCompliance` | SSM patch compliance | R | ✅ |
| `AWS::Organizations::OrganizationalUnit` | Organizations OU | G | ❌ |
| `AWS::ServiceCatalog::CloudFormationProduct` | Service Catalog CFN product | R | ✅ |
| `AWS::ServiceCatalog::CloudFormationProvisionedProduct` | Provisioned product | R | ✅ |
| `AWS::ServiceCatalog::Portfolio` | Service Catalog portfolio | R | ✅ |
| `AWS::ResourceExplorer2::Index` | Resource Explorer index | R | ✅ |
| `AWS::ResourceExplorer2::View` | Resource Explorer view | R | ❌ |
| `AWS::ResourceGroups::Group` | Resource Groups group | R | ❌ |
| `AWS::RAM::ResourceShare` | RAM resource share | R | ❌ |
| `AWS::Budgets::BudgetsAction` | Budgets action | G | ✅ |
| `AWS::BCMDataExports::Export` | BCM data export | G | ❌ |
| `AWS::CE::CostCategory` | Cost Explorer cost category | G | ❌ |
| `AWS::FIS::ExperimentTemplate` | FIS experiment template | R | ✅ |
| `AWS::FIS::TargetAccountConfiguration` | FIS target account config | R | ❌ |
| `AWS::ResilienceHub::App` | Resilience Hub application | R | ✅ |
| `AWS::ResilienceHub::ResiliencyPolicy` | Resilience Hub policy | R | ✅ |

### 3.13 Migration & Transfer (DMS / DataSync / Transfer Family / Mainframe Modernization)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::DMS::Certificate` | DMS certificate | R | ✅ |
| `AWS::DMS::Endpoint` | DMS endpoint | R | ✅ |
| `AWS::DMS::EventSubscription` | DMS event subscription | R | ✅ |
| `AWS::DMS::ReplicationInstance` | DMS replication instance | R | ❌ |
| `AWS::DMS::ReplicationSubnetGroup` | DMS replication subnet group | R | ✅ |
| `AWS::DMS::ReplicationTask` | DMS replication task | R | ❌ |
| `AWS::DataSync::Agent` | DataSync agent | R | ❌ |
| `AWS::DataSync::LocationEFS` | DataSync EFS location | R | ✅ |
| `AWS::DataSync::LocationFSxLustre` | DataSync FSx Lustre location | R | ✅ |
| `AWS::DataSync::LocationFSxWindows` | DataSync FSx Windows location | R | ✅ |
| `AWS::DataSync::LocationHDFS` | DataSync HDFS location | R | ✅ |
| `AWS::DataSync::LocationNFS` | DataSync NFS location | R | ✅ |
| `AWS::DataSync::LocationObjectStorage` | DataSync object storage location | R | ✅ |
| `AWS::DataSync::LocationS3` | DataSync S3 location | R | ✅ |
| `AWS::DataSync::LocationSMB` | DataSync SMB location | R | ✅ |
| `AWS::DataSync::Task` | DataSync task | R | ✅ |
| `AWS::Transfer::Agreement` | Transfer Family agreement | R | ✅ |
| `AWS::Transfer::Certificate` | Transfer Family certificate | R | ✅ |
| `AWS::Transfer::Connector` | Transfer Family connector | R | ✅ |
| `AWS::Transfer::Workflow` | Transfer Family workflow | R | ✅ |
| `AWS::M2::Environment` | Mainframe Modernization environment | R | ✅ |

### 3.14 Customer Engagement (SES / Pinpoint / Connect / Connect Customer Profiles)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::SES::ConfigurationSet` | SES configuration set | R | ✅ |
| `AWS::SES::ContactList` | SES contact list | R | ✅ |
| `AWS::SES::DedicatedIpPool` | SES dedicated IP pool | R | ❌ |
| `AWS::SES::MailManagerTrafficPolicy` | SES Mail Manager traffic policy | R | ❌ |
| `AWS::SES::ReceiptFilter` | SES receipt filter | R | ✅ |
| `AWS::SES::ReceiptRuleSet` | SES receipt rule set | R | ✅ |
| `AWS::SES::Template` | SES email template | R | ✅ |
| `AWS::Pinpoint::App` | Pinpoint application | R | ✅ |
| `AWS::Pinpoint::ApplicationSettings` | Pinpoint app settings | R | ✅ |
| `AWS::Pinpoint::Campaign` | Pinpoint campaign | R | ✅ |
| `AWS::Pinpoint::EmailChannel` | Pinpoint email channel | R | ✅ |
| `AWS::Pinpoint::EmailTemplate` | Pinpoint email template | R | ✅ |
| `AWS::Pinpoint::EventStream` | Pinpoint event stream | R | ✅ |
| `AWS::Pinpoint::InAppTemplate` | Pinpoint in-app template | R | ✅ |
| `AWS::Pinpoint::Segment` | Pinpoint segment | R | ✅ |
| `AWS::Connect::Instance` | Connect instance | R | ✅ |
| `AWS::Connect::PhoneNumber` | Connect phone number | R | ✅ |
| `AWS::Connect::PredefinedAttribute` | Connect predefined attribute | R | ❌ |
| `AWS::Connect::Prompt` | Connect prompt | R | ❌ |
| `AWS::Connect::QuickConnect` | Connect quick connect | R | ✅ |
| `AWS::Connect::RoutingProfile` | Connect routing profile | R | ❌ |
| `AWS::Connect::Rule` | Connect rule | R | ❌ |
| `AWS::Connect::SecurityProfile` | Connect security profile | R | ❌ |
| `AWS::Connect::TaskTemplate` | Connect task template | R | ❌ |
| `AWS::Connect::User` | Connect user | R | ❌ |
| `AWS::CustomerProfiles::Domain` | Customer Profiles domain | R | ✅ |
| `AWS::CustomerProfiles::ObjectType` | Customer Profiles object type | R | ✅ |

### 3.15 End User Computing (WorkSpaces / AppStream / Lightsail)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::WorkSpaces::ConnectionAlias` | WorkSpaces connection alias | R | ✅ |
| `AWS::WorkSpaces::Workspace` | WorkSpaces desktop | R | ✅ |
| `AWS::AppStream::AppBlockBuilder` | AppStream app block builder | R | ❌ |
| `AWS::AppStream::Application` | AppStream application | R | ✅ |
| `AWS::AppStream::DirectoryConfig` | AppStream directory config | R | ✅ |
| `AWS::AppStream::Fleet` | AppStream fleet | R | ✅ |
| `AWS::AppStream::Stack` | AppStream stack | R | ✅ |
| `AWS::Lightsail::Bucket` | Lightsail bucket | R | ✅ |
| `AWS::Lightsail::Certificate` | Lightsail certificate | R | ✅ |
| `AWS::Lightsail::Disk` | Lightsail disk | R | ✅ |
| `AWS::Lightsail::StaticIp` | Lightsail static IP | R | ✅ |

### 3.16 IoT (IoT Core / IoT Wireless / IoT Analytics / IoT Events / IoT SiteWise / IoT TwinMaker / Greengrass / Panorama)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::IoT::AccountAuditConfiguration` | IoT audit config | R | ✅ |
| `AWS::IoT::Authorizer` | IoT authorizer | R | ✅ |
| `AWS::IoT::BillingGroup` | IoT billing group | R | ❌ |
| `AWS::IoT::CACertificate` | IoT CA certificate | R | ✅ |
| `AWS::IoT::CustomMetric` | IoT custom metric | R | ✅ |
| `AWS::IoT::Dimension` | IoT dimension | R | ✅ |
| `AWS::IoT::DomainConfiguration` | IoT domain configuration | R | ❌ |
| `AWS::IoT::FleetMetric` | IoT fleet metric | R | ✅ |
| `AWS::IoT::JobTemplate` | IoT job template | R | ✅ |
| `AWS::IoT::MitigationAction` | IoT mitigation action | R | ✅ |
| `AWS::IoT::Policy` | IoT policy | R | ✅ |
| `AWS::IoT::ProvisioningTemplate` | IoT provisioning template | R | ✅ |
| `AWS::IoT::ResourceSpecificLogging` | IoT resource-specific logging | R | ❌ |
| `AWS::IoT::RoleAlias` | IoT role alias | R | ✅ |
| `AWS::IoT::ScheduledAudit` | IoT scheduled audit | R | ✅ |
| `AWS::IoT::SecurityProfile` | IoT security profile | R | ✅ |
| `AWS::IoT::SoftwarePackage` | IoT software package | R | ❌ |
| `AWS::IoT::ThingGroup` | IoT thing group | R | ❌ |
| `AWS::IoT::TopicRule` | IoT topic rule | R | ❌ |
| `AWS::IoTCoreDeviceAdvisor::SuiteDefinition` | IoT Device Advisor suite | R | ❌ |
| `AWS::IoTWireless::Destination` | IoT Wireless destination | R | ❌ |
| `AWS::IoTWireless::DeviceProfile` | IoT Wireless device profile | R | ❌ |
| `AWS::IoTWireless::FuotaTask` | IoT Wireless FUOTA task | R | ✅ |
| `AWS::IoTWireless::MulticastGroup` | IoT Wireless multicast group | R | ✅ |
| `AWS::IoTWireless::NetworkAnalyzerConfiguration` | IoT Wireless network analyzer | R | ❌ |
| `AWS::IoTWireless::ServiceProfile` | IoT Wireless service profile | R | ✅ |
| `AWS::IoTWireless::TaskDefinition` | IoT Wireless task definition | R | ❌ |
| `AWS::IoTWireless::WirelessGateway` | IoT Wireless gateway | R | ❌ |
| `AWS::IoTAnalytics::Channel` | IoT Analytics channel | R | ✅ |
| `AWS::IoTAnalytics::Dataset` | IoT Analytics dataset | R | ✅ |
| `AWS::IoTAnalytics::Datastore` | IoT Analytics datastore | R | ✅ |
| `AWS::IoTAnalytics::Pipeline` | IoT Analytics pipeline | R | ✅ |
| `AWS::IoTEvents::AlarmModel` | IoT Events alarm model | R | ✅ |
| `AWS::IoTEvents::DetectorModel` | IoT Events detector model | R | ✅ |
| `AWS::IoTEvents::Input` | IoT Events input | R | ✅ |
| `AWS::IoTSiteWise::Asset` | IoT SiteWise asset | R | ❌ |
| `AWS::IoTSiteWise::AssetModel` | IoT SiteWise asset model | R | ✅ |
| `AWS::IoTSiteWise::Dashboard` | IoT SiteWise dashboard | R | ✅ |
| `AWS::IoTSiteWise::Gateway` | IoT SiteWise gateway | R | ✅ |
| `AWS::IoTSiteWise::Portal` | IoT SiteWise portal | R | ✅ |
| `AWS::IoTSiteWise::Project` | IoT SiteWise project | R | ✅ |
| `AWS::IoTTwinMaker::ComponentType` | IoT TwinMaker component type | R | ✅ |
| `AWS::IoTTwinMaker::Entity` | IoT TwinMaker entity | R | ✅ |
| `AWS::IoTTwinMaker::Scene` | IoT TwinMaker scene | R | ✅ |
| `AWS::IoTTwinMaker::SyncJob` | IoT TwinMaker sync job | R | ✅ |
| `AWS::IoTTwinMaker::Workspace` | IoT TwinMaker workspace | R | ✅ |
| `AWS::GreengrassV2::ComponentVersion` | Greengrass component version | R | ✅ |
| `AWS::Panorama::Package` | Panorama package | R | ✅ |
| `AWS::GroundStation::Config` | Ground Station config | R | ✅ |
| `AWS::GroundStation::DataflowEndpointGroup` | Ground Station dataflow endpoint | R | ✅ |
| `AWS::GroundStation::MissionProfile` | Ground Station mission profile | R | ✅ |

### 3.17 Media (CloudFront 외 Media 서비스 / IVS / GameLift)

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::MediaConnect::FlowEntitlement` | MediaConnect flow entitlement | R | ✅ |
| `AWS::MediaConnect::FlowSource` | MediaConnect flow source | R | ✅ |
| `AWS::MediaConnect::FlowVpcInterface` | MediaConnect flow VPC interface | R | ✅ |
| `AWS::MediaPackage::PackagingConfiguration` | MediaPackage packaging config | R | ✅ |
| `AWS::MediaPackage::PackagingGroup` | MediaPackage packaging group | R | ✅ |
| `AWS::MediaTailor::PlaybackConfiguration` | MediaTailor playback config | R | ✅ |
| `AWS::IVS::Channel` | IVS channel | R | ✅ |
| `AWS::IVS::PlaybackKeyPair` | IVS playback key pair | R | ✅ |
| `AWS::IVS::RecordingConfiguration` | IVS recording config | R | ✅ |
| `AWS::GameLift::Build` | GameLift game build | R | ❌ |
| `AWS::GameLift::ContainerFleet` | GameLift container fleet | R | ❌ |
| `AWS::GameLift::ContainerGroupDefinition` | GameLift container group | R | ❌ |
| `AWS::GameLift::GameServerGroup` | GameLift game server group | R | ❌ |
| `AWS::GameLift::Location` | GameLift location | R | ❌ |
| `AWS::GameLift::MatchmakingRuleSet` | GameLift matchmaking rule set | R | ❌ |
| `AWS::GameLift::Script` | GameLift script | R | ❌ |

### 3.18 Robotics & Service Discovery & Misc

| Resource Type | 설명 | Scope | DAILY |
|---|---|---|---|
| `AWS::RoboMaker::RobotApplication` | RoboMaker robot application | R | ✅ |
| `AWS::RoboMaker::RobotApplicationVersion` | RoboMaker robot app version | R | ✅ |
| `AWS::RoboMaker::SimulationApplication` | RoboMaker simulation app | R | ✅ |
| `AWS::ServiceDiscovery::HttpNamespace` | Cloud Map HTTP namespace | R | ✅ |
| `AWS::ServiceDiscovery::Instance` | Cloud Map instance | R | ✅ |
| `AWS::ServiceDiscovery::PublicDnsNamespace` | Cloud Map public DNS namespace | R | ✅ |
| `AWS::ServiceDiscovery::Service` | Cloud Map service | R | ✅ |
| `AWS::ElastiCache::CacheCluster` | ElastiCache cache cluster | R | ❌ |
| `AWS::ElastiCache::ReplicationGroup` | ElastiCache replication group | R | ❌ |
| `AWS::APS::RuleGroupsNamespace` | Managed Prometheus rule group namespace | R | ✅ |
| `AWS::Grafana::Workspace` | Managed Grafana workspace | R | ✅ |
| `AWS::Location::APIKey` | Location Service API key | R | ❌ |
| `AWS::Deadline::Fleet` | Deadline Cloud fleet | R | ❌ |
| `AWS::Deadline::LicenseEndpoint` | Deadline Cloud license endpoint | R | ❌ |
| `AWS::Deadline::Monitor` | Deadline Cloud monitor | R | ❌ |
| `AWS::Deadline::QueueEnvironment` | Deadline Cloud queue environment | R | ❌ |
| `AWS::Deadline::QueueFleetAssociation` | Deadline Cloud queue fleet association | R | ❌ |
| `AWS::Deadline::StorageProfile` | Deadline Cloud storage profile | R | ❌ |

---

## 4. 운영 검증 명령

```bash
# 본 계정·리전에서 AWS Config 가 인식하는 supported resource types 조회
aws configservice describe-configuration-recorders --profile <profile>
# Recorder 의 recording_group.resourceTypes / exclusionByResourceTypes 확인

# 발견된 모든 resource types 의 카운트 (실제 발생 면적 파악 — EXCLUSION 후보 식별 입력)
aws configservice get-discovered-resource-counts --profile <profile> \
  --query 'resourceCounts[*].[resourceType,count]' --output table

# 특정 타입의 DAILY override 가능성 확인 (API reject 여부)
# 실제 적용은 본 프로젝트 모듈의 recording_overrides 로:
#   recording_overrides = [{
#     description         = "Lower cadence for high-churn / low-risk resources"
#     resource_types      = ["AWS::EC2::NetworkInterface", "AWS::EC2::Volume"]
#     recording_frequency = "DAILY"
#   }]
```

---

## 5. 동기화 정책

- 본 문서는 **2026-05-22** 시점의 AWS Config 공식 문서 기준 — 변경 가능.
- AWS 가 신규 resource type 출시 시 EXCLUSION 모델 하에서는 자동으로 기록 면적에 포함되므로 본 문서 갱신은 *권고* 사항 (운영 차단 X).
- DAILY 후보 추가 검토 시 AWS API 가 reject 하면 본 문서의 `DAILY ❌ → ✅` 마이그레이션이 발생했을 가능성 — AWS 공식 문서 재확인 + 본 문서 갱신.
- 권위 SSOT 는 항상 [AWS 공식 docs](https://docs.aws.amazon.com/config/latest/APIReference/API_RecordingModeOverride.html) 이며 본 문서는 운영 편의용 mirror.
