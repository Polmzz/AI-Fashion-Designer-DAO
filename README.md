# 🎨 AI Fashion Designer DAO

A decentralized autonomous organization where the community votes on AI-generated fashion designs, and winning creators receive royalties from the voting pool.

## ✨ Features

- 👗 **Design Submission**: Creators can submit fashion designs with metadata and stake STX
- 🗳️ **Community Voting**: Users vote with STX on designs they like
- 💰 **Royalty Distribution**: Winners receive royalties from the voting pool
- 📊 **Reputation System**: Track user stats and reputation scores
- ⚙️ **DAO Governance**: Configurable voting duration, stake amounts, and fees

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- STX tokens for staking and voting

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Run `clarinet check` to verify the contract

## 📋 Contract Functions

### 🎯 Core Functions

#### `submit-design`
Submit a new fashion design for community voting.

```clarity
(submit-design "Summer Collection" "Vibrant beach wear design" "ipfs://design-metadata-uri")
```

**Parameters:**
- `title` (string-ascii 64): Design title
- `description` (string-ascii 256): Design description  
- `metadata-uri` (string-ascii 512): URI to design metadata/images

**Requirements:**
- Title, description, and metadata URI must be non-empty
- Sender must have sufficient STX for minimum stake

#### `vote-on-design`
Vote on a submitted design with STX tokens.

```clarity
(vote-on-design u1 true u500000)
```

**Parameters:**
- `design-id` (uint): ID of the design to vote on
- `vote-for` (bool): true for yes, false for no
- `vote-amount` (uint): Amount of STX to stake with vote

**Requirements:**
- Haven't voted on this design before
- Voting period is still active
- Have sufficient STX balance

#### `finalize-voting`
Close voting period and determine winner.

```clarity
(finalize-voting u1)
```

**Requirements:**
- Voting period has ended
- Can be called by anyone

#### `claim-royalties`
Claim rewards for voting on winning designs.

```clarity
(claim-royalties u1)
```

**Requirements:**
- Design won the vote
- You voted "yes" on the winning design
- Royalties haven't been claimed yet

#### `claim-creator-stake`
Creators can reclaim their initial stake after voting ends.

```clarity
(claim-creator-stake u1)
```

**Requirements:**
- You're the creator of the design
- Voting has concluded
- Stake hasn't been claimed yet

### 📖 Read-Only Functions

#### `get-design`
Get design details by ID.

```clarity
(get-design u1)
```

#### `get-user-stats`
Get user statistics and reputation.

```clarity
(get-user-stats 'SP1ABC...)
```

#### `is-voting-active`
Check if voting is still active for a design.

```clarity
(is-voting-active u1)
```

### ⚙️ Admin Functions (Contract Owner Only)

#### `update-voting-duration`
Set voting period duration in blocks.

```clarity
(update-voting-duration u2016)  ;; ~2 weeks
```

#### `update-min-stake`
Set minimum stake amount for design submission.

```clarity
(update-min-stake u2000000)  ;; 2 STX
```

#### `update-dao-fee`
Set DAO fee percentage (basis points).

```clarity
(update-dao-fee u250)  ;; 2.5%
```

## 🎮 Usage Example

1. **Submit Design** 🎨
   ```clarity
   (submit-design "Cyberpunk Jacket" "Neon-lit futuristic jacket design" "ipfs://QmX...")
   ```

2. **Community Votes** 🗳️
   ```clarity
   (vote-on-design u1 true u1000000)  ;; Vote YES with 1 STX
   ```

3. **Finalize Results** 🏆
   ```clarity
   (finalize-voting u1)
   ```

4. **Claim Rewards** 💎
   ```clarity
   (claim-royalties u1)  ;; Winning voters get rewards
   (claim-creator-stake u1)  ;; Creator gets stake back
   ```

## 💡 How It Works

1. **Design Submission**: Creators stake STX and submit fashion designs
2. **Voting Period**: Community votes with STX on submitted designs
3. **Winner Selection**: Designs with more "yes" votes win
4. **Reward Distribution**: 
   - Winning voters split the voting pool proportionally
   - DAO takes a small fee
   - Creators get their stake back

## 🔧 Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| Voting Duration | 1008 blocks | ~1 week voting period |
| Min Stake | 1,000,000 μSTX | 1 STX minimum stake |
| DAO Fee | 100 basis points | 1% fee to DAO |

## 🏗️ Contract Architecture

- **Design Storage**: Maps storing design metadata and voting results
- **Vote Tracking**: Individual vote records with amounts and timestamps  
- **User Stats**: Reputation and activity tracking
- **Royalty Pools**: Reward distribution pools per design

## 🔐 Security Features

- ✅ Owner-only admin functions
- ✅ Voting period enforcement
- ✅ Double-voting prevention
- ✅ Balance verification before transfers
- ✅ Input validation and error handling

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `clarinet check` to verify
5. Submit a pull request

## 📄 License

This project is open source and available under the MIT License.

---

*Built with ❤️ for the fashion and crypto community*
