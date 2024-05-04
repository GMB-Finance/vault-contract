
# Vault Contract

A robust and dynamic smart contract for token locking on the Ethereum blockchain, influenced by Curve's veToken model but with significant modifications to enhance user incentives and engagement. This project leverages OpenZeppelin's contracts to ensure security and adds a distinctive mechanism where the voting power increases over time rather than declining. It also introduces the ability for users to re-lock their tokens, further increasing their voting power the longer they commit their holdings.

## Features

- **Token Locking with Increasing Voting Power**: Implements a novel voting power mechanism that increases over the lock period, encouraging longer-term holding and enhancing governance participation. Users can also extend their lock duration through re-locking, boosting their influence within the ecosystem.
- **Fee Collection and Reward Distribution**: Efficiently collects fees on deposits and distributes rewards, aligning with the duration tokens are held, thus promoting longer lock-ins.
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
