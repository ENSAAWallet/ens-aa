// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Resolver} from "@ensdomains/ens-contracts/contracts/resolvers/Resolver.sol";
import {INameWrapper, PARENT_CANNOT_CONTROL, CANNOT_UNWRAP, CANNOT_SET_RESOLVER} from "@ensdomains/ens-contracts/contracts/wrapper/INameWrapper.sol";

import {_packValidationData} from "./libraries/Helpers.sol";
import {LibCoinType} from "./libraries/CoinType.sol";
import {LibKeyScore} from "./libraries/KeyScore.sol";
import {IENSAccount} from "./interfaces/IENSAccount.sol";
import {BaseAccount, IEntryPoint, UserOperation} from "./abstracts/BaseAccount.sol";
import {TokenCallbackHandler} from "./TokenCallbackHandler.sol";

contract ENSAccount is
    IENSAccount,
    BaseAccount,
    TokenCallbackHandler,
    UUPSUpgradeable,
    Initializable
{
    using ECDSA for bytes32;

    struct AddressRecord {
        bytes addr;
        uint256 score; // score means the priority of the address
    }

    struct OwnerRecord {
        uint256 coinType;
        bytes addr;
    }

    bytes32 public node;
    // The expiry date of the domain, in seconds since the Unix epoch.
    uint64 public expiry;
    OwnerRecord public owner;
    // CoinType => AddressRecord
    mapping(uint256 => AddressRecord) public addresses;
    INameWrapper public immutable nameWrapper;
    Resolver public immutable resolver;
    IEntryPoint private immutable _entryPoint;

    event ENSAccountInitialized(
        IEntryPoint indexed entryPoint,
        Resolver indexed resolver,
        INameWrapper nameWrapper,
        bytes32 indexed node,
        address owner,
        uint64 expiry
    );

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    // Require the function call went through EntryPoint or owner
    modifier onlyEntryPointOrOwner() {
        require(
            msg.sender == address(entryPoint()) || msg.sender == getOwner(),
            "account: not Owner or EntryPoint"
        );
        _;
    }

    modifier notExpired() {
        require(block.timestamp <= expire, "expired domain");
        _;
    }

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(
            msg.sender == getOwner() || msg.sender == address(this),
            "only owner"
        );
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(
        IEntryPoint _ep,
        INameWrapper _nameWrapper,
        Resolver _resolver
    ) {
        _entryPoint = _ep;
        nameWrapper = _nameWrapper;
        resolver = _resolver;
        _disableInitializers();
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of ENSAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(bytes32 _node) public virtual initializer {
        _initialize(_node);
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    function getOwner() public view notExpired returns (address) {
        bytes memory addr = owner.addr;
        return addr.length == 0 ? address(0) : _bytesToAddress(addr);
    }

    function getSignMode(uint256 nonce) public pure returns (uint256) {
        // Use coinType to indicate the sign mode
        // TODO: extend other sign modes (e.g. multi signature of multi coinType)
        return nonce == 0 ? LibCoinType.COIN_TYPE_ETH : (nonce >> 64);
    }

    function updateExiry() public returns (uint64) {
        require(
            nameWrapper.allFusesBurned(
                node,
                PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | CANNOT_SET_RESOLVER
            ),
            "fuses restriction"
        );
        (, , expiry) = nameWrapper.getData(uint256(node));
        return expiry;
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(
        address payable withdrawAddress,
        uint256 amount
    ) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function migrateCoinType(
        uint256[] calldata _coinTypes
    ) external notExpired {
        for (uint256 i = 0; i < _coinTypes.length; ++i) {
            addresses[_coinTypes[i]].addr = resolver.addr(node, _coinTypes[i]);
        }
    }

    function updateNode(
        uint256 coinType,
        bytes calldata addr
    ) external notExpired {
        require(
            msg.sender == address(resolver),
            "only allow resolver to update "
        );
        addresses[coinType].addr = addr;
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    )
        external
        virtual
        override
        onlyEntryPointOrOwner
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external onlyEntryPointOrOwner {
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(
        address[] calldata dest,
        bytes[] calldata func
    ) external onlyEntryPointOrOwner {
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    function _initialize(bytes32 _node) internal virtual {
        require(
            nameWrapper.allFusesBurned(
                _node,
                PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | CANNOT_SET_RESOLVER
            ),
            "fuses restriction"
        );
        // only active eth address first
        bytes memory ethAddr = resolver.addr(_node, LibCoinType.COIN_TYPE_ETH);
        addresses[LibCoinType.COIN_TYPE_ETH] = AddressRecord({
            score: 1, // highest score
            addr: ethAddr
        });

        owner = OwnerRecord({
            coinType: LibCoinType.COIN_TYPE_ETH,
            addr: ethAddr
        });

        node = _node;
        (, , expiry) = nameWrapper.getData(uint256(_node));
        emit ENSAccountInitialized(
            _entryPoint,
            resolver,
            nameWrapper,
            _node,
            _bytesToAddress(ethAddr),
            expiry
        );
    }

    /// implement template method of BaseAccount
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        uint256 mode = getSignMode(userOp.nonce);
        if (mode == LibCoinType.COIN_TYPE_ETH) {
            AddressRecord memory record = addresses[mode];
            if (
                record.score == LibKeyScore.DISABLE ||
                record.score > LibKeyScore.VALIDATION_THREADHOLD
            ) {
                revert UnvalidKeyScore(record.score);
            }
            return
                _packValidationData(
                    _bytesToAddress(record.addr) !=
                        hash.recover(userOp.signature), // sigFailed
                    uint48(expiry),
                    0
                );
        }
        revert UnSupportedSignMode(mode);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override {
        (newImplementation);
        _onlyOwner();
    }

    function _bytesToAddress(
        bytes memory b
    ) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }
}
