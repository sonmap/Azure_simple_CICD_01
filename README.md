# Azure Simple CI/CD 01

Azure DevOps와 Terraform으로 아래의 아주 단순한 웹 서비스를 배포하는 예제입니다.

```text
User
  |
  | HTTP :80
  v
Azure Standard Public Load Balancer
  |
  | Backend pool / Health probe
  v
Ubuntu Linux VM (private IP only)
  |
  v
Nginx
```

VM에는 Public IP와 SSH 인바운드 규칙을 만들지 않습니다. 외부 사용자는 Load Balancer의 Public IP 80번 포트로만 접속합니다.

## 배포 단계

| 단계 | 디렉터리 | 구성 |
|---|---|---|
| 00 | `00-state` | Terraform remote state용 Resource Group, Storage Account, Blob Container |
| 10 | `10-network` | Resource Group, VNet, Subnet, NSG, Public IP, Standard Load Balancer |
| 20 | `20-vm` | Ubuntu VM 1대, NIC, LB backend pool 연결 |
| 30 | `30-nginx` | VM Custom Script Extension으로 Nginx 설치 및 샘플 페이지 배포 |

각 단계는 별도의 remote state를 사용합니다.

```text
00-state.tfstate
10-network.tfstate
20-vm.tfstate
30-nginx.tfstate
```

## 사전 준비

1. Azure DevOps Project에서 이 GitHub 저장소를 연결합니다.
2. Azure Resource Manager Service Connection을 만듭니다.
   - 권장: Workload Identity Federation
   - 기본 이름: `sc-azure-simple-cicd`
3. 서비스 연결의 Service Principal에 대상 Subscription의 `Contributor` 권한을 부여합니다.
4. `azure-pipelines.yml`에서 다음 값을 확인합니다.

```yaml
azureServiceConnection: 'sc-azure-simple-cicd'
location: 'koreacentral'
prefix: 'simplecicd'
stateResourceGroup: 'rg-simplecicd-tfstate-krc'
stateStorageAccount: 'tfstatesonmapcicd01'
stateContainer: 'tfstate'
```

`stateStorageAccount`는 Azure 전체에서 유일해야 하며, 3~24자의 영문 소문자와 숫자만 사용할 수 있습니다. 이미 사용 중이면 다른 이름으로 변경합니다.

## Azure DevOps 실행

### CI 검증

`main` push 또는 Pull Request에서는 다음 작업만 자동 실행됩니다.

- `terraform fmt -check`
- `terraform init -backend=false`
- `terraform validate`

Azure 리소스는 자동 생성하지 않으므로 예상하지 않은 비용이 발생하지 않습니다.

### CD 배포

Azure DevOps에서 Pipeline을 수동 실행하고 다음 Parameter를 선택합니다.

```text
Deploy Azure resources: true
```

그 후 다음 순서로 실행됩니다.

```text
CI_Validate
  -> CD_00_State
  -> CD_10_Network
  -> CD_20_VM
  -> CD_30_Nginx
```

00단계는 첫 실행에서 local state로 Storage Account와 Container를 만든 후 `00-state.tfstate`를 새 remote backend로 자동 이전합니다. 두 번째 실행부터는 remote state를 직접 사용합니다.

20단계는 `20-vm/no-login.pub`의 고정 공개키를 사용하므로 파이프라인을 다시 실행해도 SSH 키 변경 때문에 VM이 교체되지 않습니다. 이 키의 개인키는 저장하지 않으며 VM의 SSH 포트도 외부에 열지 않습니다. 실제 관리 접속이 필요하면 자신의 공개키와 Azure Bastion 또는 사설 관리 경로를 사용해야 합니다.

Nginx 설치는 30단계의 Azure VM Extension으로 수행합니다.

## 접속 확인

30단계 로그의 마지막에서 URL을 확인합니다.

```text
Website URL: http://<LOAD_BALANCER_PUBLIC_IP>
```

또는 Azure CLI로 확인합니다.

```bash
az network public-ip show \
  --resource-group rg-simplecicd-krc \
  --name pip-simplecicd-lb \
  --query ipAddress \
  --output tsv
```

브라우저에서 아래 주소로 접속합니다.

```text
http://<LOAD_BALANCER_PUBLIC_IP>
```

## 주요 보안/네트워크 사항

- VM Public IP 없음
- SSH 22번 포트 외부 미개방
- 외부 인바운드는 HTTP 80만 허용
- Azure Load Balancer health probe 허용
- Standard Load Balancer outbound rule을 명시하여 VM의 `apt-get` 인터넷 통신 제공
- Terraform state Storage Account는 TLS 1.2, private container, Blob versioning 사용

## 비용 주의

이 예제는 작은 `Standard_B1s` VM을 사용하지만 Public IP, Standard Load Balancer, 디스크, Storage Account 등에 비용이 발생할 수 있습니다. 테스트가 끝나면 Terraform state의 의존 관계를 고려해 `30 -> 20 -> 10` 역순으로 제거하고 마지막에 00 state 저장소를 정리합니다.
