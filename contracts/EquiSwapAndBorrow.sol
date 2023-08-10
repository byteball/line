// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface EquilibreRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }

	function weth() external returns (address);

	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
		uint amountIn,
		uint amountOutMin,
		route[] calldata routes,
		address to,
		uint deadline
	) external;

	function swapExactETHForTokensSupportingFeeOnTransferTokens(
		uint amountOutMin,
		route[] calldata routes,
		address to,
		uint deadline
	) external payable;
}


interface ILine is IERC20 {
	function collateral_token_address() external returns (address);
	function loanNFT() external returns (IERC721);
	function borrow(uint collateral_amount) external returns (uint);
}

contract EquiSwapAndBorrow is IERC721Receiver {

	using SafeERC20 for IERC20;
	using SafeERC20 for ILine;

	EquilibreRouter public constant router = EquilibreRouter(0xA7544C409d772944017BB95B99484B6E0d7B6388);
	ILine public constant line = ILine(0x31f8d38df6514b6cc3C360ACE3a2EFA7496214f6);
	IERC20 public immutable collateral_token;

	constructor () {
		collateral_token = IERC20(line.collateral_token_address());
		collateral_token.approve(address(line), type(uint).max);
	}

	function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external pure returns (bytes4) {
		return IERC721Receiver.onERC721Received.selector;
	}

	function swapAndBorrow(uint amountIn, uint amountOutMin, EquilibreRouter.route[] calldata routes, uint deadline) external payable {
		address input_token = routes[0].from;
		address output_token = routes[routes.length - 1].to;
		require(output_token == address(collateral_token), "should buy collateral token");

		bool isETH = input_token == router.weth();
		if (isETH) {
			require(msg.value == amountIn, "wrong ETH amount");
			router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(amountOutMin, routes, address(this), deadline);
		}
		else {
			require(msg.value == 0, "ETH with tokens");
			IERC20(input_token).safeTransferFrom(msg.sender, address(this), amountIn);
			uint allowance = IERC20(input_token).allowance(address(this), address(router));
			if (allowance < amountIn)
				IERC20(input_token).approve(address(router), type(uint).max);
			router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, amountOutMin, routes, address(this), deadline);
		}

		uint collateral_amount = collateral_token.balanceOf(address(this));
		require(collateral_amount > 0, "swap yielded 0");
		
		uint loan_num = line.borrow(collateral_amount);
		line.safeTransfer(msg.sender, line.balanceOf(address(this)));
		line.loanNFT().safeTransferFrom(address(this), msg.sender, loan_num);
	}

}
