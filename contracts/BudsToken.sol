// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@zetachain/protocol-contracts/contracts/evm/interfaces/ZetaInterfaces.sol";
import "@zetachain/protocol-contracts/contracts/evm/tools/ZetaInteractor.sol";

interface CrossChainTokensErrors {
    error InvalidMessageType();
}

contract BudsToken is ERC20, ZetaInteractor, ZetaReceiver, CrossChainTokensErrors {
    bytes32 public constant CROSS_CHAIN_TRANSFER_MESSAGE =
        keccak256("CROSS_CHAIN_TRANSFER");

    IERC20 internal immutable _zetaToken;

    ZetaTokenConsumer private immutable _zetaConsumer;

    constructor(
        string memory name,
        string memory symbol,
        address connectorAddress,
        address zetaTokenAddress,
        address zetaConsumerAddress
    ) ERC20(name, symbol) ZetaInteractor(connectorAddress) {
        _zetaToken = IERC20(zetaTokenAddress);
        _zetaConsumer = ZetaTokenConsumer(zetaConsumerAddress);
    }

    /**
     * @dev Cross-chain functions
     */

    function crossChainTransfer(
        uint256 crossChainId,
        address to,
        uint256 amount
    ) external payable {
        if (!_isValidChainId(crossChainId)) revert InvalidDestinationChainId();

        uint256 crossChainGas = 2 * (10 ** 18);
        uint256 zetaValueAndGas = _zetaConsumer.getZetaFromEth{ value: msg.value }(
            address(this),
            crossChainGas
        );
        _zetaToken.approve(address(connector), zetaValueAndGas);

        _burn(msg.sender, amount);

        connector.send(
            ZetaInterfaces.SendInput({
                destinationChainId: crossChainId,
                destinationAddress: interactorsByChainId[crossChainId],
                destinationGasLimit: 500000,
                message: abi.encode(CROSS_CHAIN_TRANSFER_MESSAGE, amount, msg.sender, to),
                zetaValueAndGas: zetaValueAndGas,
                zetaParams: abi.encode("")
            })
        );
    }

    function onZetaMessage(ZetaInterfaces.ZetaMessage calldata zetaMessage) external override isValidMessageCall(zetaMessage) {
        (bytes32 messageType, uint256 amount, , address to) = abi.decode(
            zetaMessage.message,
            (bytes32, uint256, address, address)
        );

        if (messageType != CROSS_CHAIN_TRANSFER_MESSAGE) revert InvalidMessageType();

        _mint(to, amount);
    }

    function onZetaRevert(ZetaInterfaces.ZetaRevert calldata zetaRevert) external override isValidRevertCall(zetaRevert) {
        (bytes32 messageType, uint256 amount, address from) = abi.decode(
            zetaRevert.message,
            (bytes32, uint256, address)
        );

        if (messageType != CROSS_CHAIN_TRANSFER_MESSAGE) revert InvalidMessageType();

        _mint(from, amount);
    }
}
