// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "@ensdomains/ens-contracts/contracts/resolvers/Resolver.sol";
import "@ensdomains/ens-contracts/contracts/wrapper/NameWrapper.sol";

import "./libraries/Helpers.sol";
import "./interfaces/IENSAccount.sol";
import "./abstracts/BaseAccount.sol";
import "./TokenCallbackHandler.sol";

contract ENSAccount is
    IENSAccount,
    BaseAccount,
    TokenCallbackHandler,
    UUPSUpgradeable,
    Initializable
{
    using ECDSA for bytes32;

    uint256 private constant COIN_TYPE_ETH = 60;

    uint64 public ensExpiry;
    bytes32 public ensNode;
    mapping(uint256 => bytes) addresses;
    NameWrapper public immutable ensNameWrapper;
    Resolver public immutable ensResolver;
    IEntryPoint private immutable _entryPoint;

    event ENSAccountInitialized(
        IEntryPoint indexed entryPoint,
        Resolver indexed ensResolver,
        bytes32 indexed node,
        NameWrapper ensNameWrapper,
        address owner,
        uint64 ensExpiry
    );

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(
        IEntryPoint anEntryPoint,
        NameWrapper anEnsNameWrapper,
        Resolver anEnsResolver
    ) {
        _entryPoint = anEntryPoint;
        ensNameWrapper = anEnsNameWrapper;
        ensResolver = anEnsResolver;
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

    function getOwner() public view returns (address owner) {
        bytes memory a = addresses[COIN_TYPE_ETH];
        owner = a.length == 0 ? address(0) : bytesToAddress(a);
    }

    function updateNode(uint256 coinType, bytes memory a) external {
        require(
            msg.sender == address(ensResolver),
            "only allow resolver to update "
        );
        addresses[coinType] = a;
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of ENSAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(bytes32 node) public virtual initializer {
        _initialize(node);
    }

    function _initialize(bytes32 node) internal virtual {
        ensNode = node;
        (, , uint64 expiry) = ensNameWrapper.getData(uint256(node));
        require(
            ensNameWrapper.allFusesBurned(
                node,
                PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | CANNOT_SET_RESOLVER
            ),
            "fuses restriction"
        );
        ensExpiry = expiry;
        addresses[COIN_TYPE_ETH] = ensResolver.addr(node, COIN_TYPE_ETH);
        emit ENSAccountInitialized(
            _entryPoint,
            ensResolver,
            node,
            ensNameWrapper,
            getOwner(),
            ensExpiry
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
            validationData = _packValidationData(false, uint48(ensExpiry), 0);
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
        if (getOwner() != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
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

    function bytesToAddress(
        bytes memory b
    ) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }
}
