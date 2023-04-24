# ENSAA

ENS is a leading DID solution with the following characteristics.

- Easy to remember and can be resolved into the blockchain address

- Support multichain including Bitcoin, Dogcoin, etc

- Various records including `ADDRESSES`, `CONTENT`, `TEXT RECORD`, etc

- Integrated by a large number of applications

- [Namewrapper](https://ens.mirror.xyz/0M0fgqa6zw8M327TJk9VmGY__eorvLAKwUwrHEhc1MI) is an elegant permission mechanism and makes all ENS domains become ERC-1155 NFTs.

However, ENS domain are mainly used as DID for offchain domain resolution while onchain operations are based on the resolved address instead of the ENS domain. Therefore, the resolved address is the real onchain ID.

Can we have a real ENS Ethereum account as our onchain ID?

Obviously, if account abstraction can be organically combined with ENS, then this problem can be solved. Everything will also become wonderful.

- The ENS domain becomes a real ID both offchain and onchain

- Just reset the resolving address in the ENS APP, the account can be handed over automatically. Especially considering the features of SBT, EOA cannot achieve this. Also, ENS itself has a complete and flexible permission mechanism for setting the resolving address, which can meet the needs of the organizations.

- Since the ENS domain is a ERC-1155 NFT, you can manage your account by operating the NFT.

- After the launch of ENS Namewrapper, ENS has built-in flexible permission mechanism called `fuse`. Therefore, the developer does not need to implement similar mechanism in the ENSAA account and can reuse the built-in permission mechanism of ENS.

- ENSAA introduces more possibilities for recovery and security of the account. The various information on ENS is a potential source of account recovery and risk control. For example,

  - When the private key of the Ethereum address is lost, users can choose the private key of the Dogcoin address to continue using the ENSAA account, similar to the idea of the Ethereum client diversity.

  - For some high-risk operations on the account, verification can be achieved through multiple signatures of private keys in multiple chains.
  - According the rule of the `fuse`, you can recover the `ENSAccount` by its parant ens domain. For example,
    - recover `ENSAccount` of `staff.company.eth` by `company.eth`.

  - ENS also records social information (such as Twitter), providing the possibility of introducing social recovery and the keyless account.

Currently, ERC-4337 is a relatively mature account abstraction solution. At first glance, the developer only need to access ENS information during the ERC-4337 validation loop to achieve ENSAA's goals.

However, in order to prevent bundlers from being attacked, [ERC-4337 restricts the account behavior during the ERC-4337 validation loop](https://eips.ethereum.org/EIPS/eip-4337#simulation). One of the constraints is that account validation can only access storage associated with the account. Due to the fact that ENS information is stored outside of the account, this approach becomes infeasible.

This project innovatively solved this problem and achieved ENSAA that meets the ERC-4337 specification.

The basic idea is as follows

- ENS domain name uses custom `AAResolver` to record ENS information

- When the information recorded by `AAResolver` changes, callback the relevant `ENSAccount` for sync.

- Finally, The ERC-4337 validation loop of `ENSAccount` only requires accessing `ENSAccount`'s own storage for verification.

However, forcing ENS domain to use custom `AAResolver` is not feasible. Once the ENS domain switches to other `Resolver`, the binding link of `ENSDomain <-> AAResolver <-> ENSAccount` will be broken.

Therefore, this project introduces the `fuses` mechanism of the ENS Namewrapper. When creating an `ENSAccount`, `ENSAccountFactory` will check the fuses of the ENS domain to ensure that once `ENSAccount` is deployed, the ENS domain cannot switch to other `Resolver`. Of course, the expiry of the ENS domain will also be considered to ensure the binding link of `ENSDomain <-> AAResolver <-> ENSAccount`.

So, everything becomes wonderful again ~
