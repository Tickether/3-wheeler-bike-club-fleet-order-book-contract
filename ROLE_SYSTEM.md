# Role-Based Access Control System

## Overview

The FleetOrderBookPreSale contract implements a comprehensive role-based access control (RBAC) system to enhance security and reduce the risk of compromising the deployer wallet. This system allows for granular control over different administrative functions.

## Roles and Permissions

### 1. DEFAULT_ADMIN_ROLE
- **Purpose**: Highest privilege role, can grant/revoke all other roles
- **Functions**:
  - `grantSuperAdminRole(address)`
  - `revokeSuperAdminRole(address)`
  - `grantComplianceRole(address)`
  - `revokeComplianceRole(address)`
  - `grantWithdrawalRole(address)`
  - `revokeWithdrawalRole(address)`
- **Security**: Should be held by a multi-signature wallet or DAO

### 2. SUPER_ADMIN_ROLE
- **Purpose**: Core administrative functions
- **Functions**:
  - `pause()` / `unpause()`
  - `setFleetFractionPrice(uint256)`
  - `setMaxFleetOrder(uint256)`
  - `addERC20(address)` / `removeERC20(address)`
  - `setBulkFleetOrderStatus(uint256[], uint256)`
- **Use Case**: Operations team, trusted administrators



### 3. COMPLIANCE_ROLE
- **Purpose**: Manage user compliance status
- **Functions**:
  - `setCompliance(address[])`
- **Use Case**: Compliance officers, KYC/AML teams

### 4. WITHDRAWAL_ROLE
- **Purpose**: Withdraw sales from the contract
- **Functions**:
  - `withdrawFleetOrderSales(address, address)`
- **Use Case**: Treasury management, finance team

## Security Benefits

### 1. Risk Mitigation
- **Deployer Wallet Protection**: Critical functions are no longer tied to the deployer wallet
- **Compartmentalization**: Different functions require different admin addresses
- **Reduced Attack Surface**: Compromise of one admin doesn't affect all functions

### 2. Operational Flexibility
- **Multi-Signature Support**: Each role can be assigned to a multi-sig wallet
- **DAO Integration**: Roles can be managed by DAO governance
- **Temporary Access**: Roles can be granted/revoked as needed

### 3. Audit Trail
- **Event Logging**: All role changes are logged as events
- **Transparency**: Role assignments are publicly verifiable
- **Compliance**: Clear separation of duties for regulatory compliance

## Deployment and Setup

### 1. Environment Variables
Create a `.env` file with the following variables:
```bash
PRIVATE_KEY=your_deployer_private_key
SUPER_ADMIN_ADDRESS=0x...
COMPLIANCE_ADDRESS=0x...
WITHDRAWAL_ADDRESS=0x...
SUPER_ADMIN_PRIVATE_KEY=0x... # Optional, for initial setup
```

### 2. Deployment
```bash
forge script script/DeployWithRoles.s.sol --rpc-url <RPC_URL> --broadcast
```

### 3. Manual Role Assignment
If you prefer to set up roles manually after deployment:

```solidity
// Grant roles (only DEFAULT_ADMIN can do this)
fleetOrderBook.grantSuperAdminRole(superAdminAddress);
fleetOrderBook.grantComplianceRole(complianceAddress);
fleetOrderBook.grantWithdrawalRole(withdrawalAddress);

// Configure initial settings (SUPER_ADMIN can do this)
fleetOrderBook.setFleetFractionPrice(1000); // $10.00
fleetOrderBook.setMaxFleetOrder(1000);
```

## Best Practices

### 1. Role Management
- **Multi-Signature Wallets**: Use multi-sig for DEFAULT_ADMIN_ROLE
- **Role Separation**: Use different addresses for different roles
- **Regular Rotation**: Periodically rotate admin keys
- **Monitoring**: Monitor role assignments and usage

### 2. Security Considerations
- **Cold Storage**: Keep DEFAULT_ADMIN private keys in cold storage
- **Access Control**: Limit access to admin private keys
- **Backup Plans**: Have recovery procedures for lost keys
- **Testing**: Test role assignments in staging environment

### 3. Operational Procedures
- **Documentation**: Document all role assignments
- **Change Management**: Implement approval processes for role changes
- **Incident Response**: Have procedures for compromised admin accounts
- **Compliance**: Ensure role assignments meet regulatory requirements

## Role Hierarchy

DEFAULT_ADMIN_ROLE (Highest)
├── SUPER_ADMIN_ROLE
│   ├── Pause/Unpause
│   ├── Price Management
│   ├── Order Limits
│   ├── ERC20 Management
│   └── Status Updates
├── COMPLIANCE_ROLE
│   └── User Compliance
└── WITHDRAWAL_ROLE
    └── Treasury Operations
```

## Emergency Procedures

### 1. Compromised Admin Account
1. **Immediate Action**: Revoke the compromised role
2. **Investigation**: Determine the scope of compromise
3. **Recovery**: Grant role to new secure address
4. **Audit**: Review all recent transactions

### 2. Lost Private Key
1. **Assessment**: Determine which roles are affected
2. **Recovery**: Use remaining admin accounts to grant roles to new addresses
3. **Documentation**: Update all documentation and procedures
4. **Prevention**: Implement better key management practices

### 3. Multi-Signature Recovery
1. **Threshold**: Ensure sufficient signers are available
2. **Procedures**: Follow multi-sig recovery procedures
3. **Verification**: Verify new signer addresses
4. **Testing**: Test recovery procedures regularly

## Monitoring and Maintenance

### 1. Regular Tasks
- **Role Audits**: Monthly review of role assignments
- **Access Reviews**: Quarterly access control reviews
- **Key Rotation**: Annual key rotation procedures
- **Documentation Updates**: Keep procedures current

### 2. Monitoring Tools
- **Event Monitoring**: Track role grant/revoke events
- **Transaction Monitoring**: Monitor admin function calls
- **Alert Systems**: Set up alerts for unusual activity
- **Logging**: Maintain comprehensive audit logs

### 3. Compliance Reporting
- **Regulatory Reports**: Generate reports for compliance
- **Audit Trails**: Maintain audit trails for all admin actions
- **Documentation**: Keep detailed records of all changes
- **Review Cycles**: Regular compliance reviews

This role-based access control system provides a robust foundation for secure contract administration while maintaining operational flexibility and regulatory compliance. 
