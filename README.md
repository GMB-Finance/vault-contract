
# Vault Contract

A secure and dynamic smart contract for token locking on the Ethereum blockchain, inspired by Curve's veToken model. This project utilizes OpenZeppelin's contracts and incorporates a unique mechanism where the voting power declines linearly over time, enhancing governance fairness and engagement. Additionally, it allows querying the voting power at any specific block, providing flexibility and transparency for token holders.

## Features

- **Token Locking with Declining Voting Power**: Implements a voting power mechanism that decreases linearly over the lock period, inspired by Curve’s veToken model. Users can query their voting power at any specific block, ensuring transparency and adaptability in voting scenarios.
- **Fee Collection and Reward Distribution**: Securely collects fees on deposits and distributes rewards based on token holding durations.
- **Emergency Unlock Feature**: Allows for an emergency withdrawal of tokens under specific conditions, ensuring user funds' safety.
- **Enhanced Security and Role-Based Functions**: Utilizes OpenZeppelin libraries for security while providing role-based functions for administrative control.

## Getting Started

### Prerequisites

- Node.js 20.x

### Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   ```
2. Install dependencies:
   ```bash
   npm install
   ```

### Deployment

1. Compile the contract:
   ```bash
   npm run compile
   ```
2. Deploy to local blockchain:
   ```bash
   npm run deploy-sepolia
   ```

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE) file for details.
