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

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function updateExiry() public returns (uint64) {
        (, , expiry) = nameWrapper.getData(uint256(node));
        return expiry;
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

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

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(
            msg.sender == getOwner() || msg.sender == address(this),
            "only owner"
        );
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(
        address[] calldata dest,
        bytes[] calldata func
    ) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    function getOwner() public view returns (address) {
        bytes memory addr = owner.addr;
        return addr.length == 0 ? address(0) : _bytesToAddress(addr);
    }

    function updateNode(uint256 coinType, bytes memory addr) external {
        require(
            msg.sender == address(resolver),
            "only allow resolver to update "
        );
        addresses[coinType].addr = addr;
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of ENSAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(bytes32 _node) public virtual initializer {
        _initialize(_node);
    }

    function _initialize(bytes32 _node) internal virtual {
        (, , expiry) = nameWrapper.getData(uint256(_node));
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
        emit ENSAccountInitialized(
            _entryPoint,
            resolver,
            nameWrapper,
            _node,
            _bytesToAddress(ethAddr),
            expiry
        );
    }

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(
            msg.sender == address(entryPoint()) || msg.sender == getOwner(),
            "account: not Owner or EntryPoint"
        );
    }

    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external virtual override returns (uint256 validationData) {
        _requireFromEntryPoint();
        validationData = _validateSignature(userOp, userOpHash);
        if (validationData == 0) {
            validationData = _packValidationData(false, uint48(expiry), 0);
        }
        _validateNonce(userOp.nonce);
        _payPrefund(missingAccountFunds);
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
            if (_bytesToAddress(record.addr) != hash.recover(userOp.signature))
                return SIG_VALIDATION_FAILED;
            return 0;
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

    function getSignMode(uint256 nonce) public pure returns (uint256) {
        // Use coinType to indicate the sign mode
        // TODO: extend other sign modes (e.g. multi signature of multi coinType)
        return nonce == 0 ? LibCoinType.COIN_TYPE_ETH : (nonce >> 64);
    }
}
