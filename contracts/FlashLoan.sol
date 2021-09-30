// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;
import { FlashLoanReceiverBase } from "./FlashLoanReceiverBase.sol";
import { ILendingPool, ILendingPoolAddressesProvider, IERC20 } from "./Interfaces.sol";
import { SafeMath } from "./Libraries.sol";
import "./Ownable.sol";
import {ISwapRouter} from "ISwapRouter.sol";
import {TransferHelper} from "TransferHelper.sol";

/*
* A contract that executes the following logic in a single atomic transaction:
*
*   1. Gets a batch flash loan of AAVE, DAI and LINK
*   2. Deposits all of this flash liquidity onto the Aave V2 lending pool
*   3. Borrows 100 LINK based on the deposited collateral
*   4. Repays 100 LINK and unlocks the deposited collateral
*   5. Withdrawls all of the deposited collateral (AAVE/DAI/LINK)
*   6. Repays batch flash loan including the 9bps fee
*
*/
contract BatchFlashDemo is FlashLoanReceiverBase, Ownable {
    
    ILendingPoolAddressesProvider provider;
    using SafeMath for uint256;
    uint256 amount;
    address lendingPoolAddr;
    ISwapRouter public immutable swapRouter;
    uint24 public constant poolFee = 3000;
    
    // kovan reserve asset addresses
    address kovanAave = 0xB597cd8D3217ea6477232F9217fa70837ff667Af;
    address kovanDai = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;
    address kovanLink = 0xAD5ce863aE3E4E9394Ab43d4ba0D80f419F61789;
    address kovanADai = 0xdCf0aF9e59C002FA3AA091a46196b37530FD48a8;
    // aDai address: 0xdCf0aF9e59C002FA3AA091a46196b37530FD48a8
    // addressProvider:  0x88757f2f99175387ab4c6a4b3067c77a695b0349
    // https://github.com/Uniswap/v3-periphery/blob/main/deploys.md
    // SwapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
    
    event Log(string indexed sstring, uint256 indexed aamount);
    
    
    // intantiate lending pool addresses provider and get lending pool address
    constructor(ILendingPoolAddressesProvider _addressProvider, ISwapRouter _swapRouter) FlashLoanReceiverBase(_addressProvider) {
        provider = _addressProvider;
        lendingPoolAddr = provider.getLendingPool();
        swapRouter  = _swapRouter;
    }

    /**
        This function is called after your contract has received the flash loaned amount
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {
        emit Log("amounts: ", amounts[0]);
        emit Log("premiums: ", premiums[0]);
        
        // initialise lending pool instance
        ILendingPool lendingPool = ILendingPool(lendingPoolAddr);
        
        // deposits the flashed AAVE, DAI and Link liquidity onto the lending pool
        flashDeposit(lendingPool, amounts[0]);

        //uint256 borrowAmt = 100 * 1e18; // to borrow 100 units of x asset
        
        // borrows 'borrowAmt' amount of LINK using the deposited collateral
        //flashBorrow(lendingPool, kovanLink, borrowAmt);
        
        // repays the 'borrowAmt' mount of LINK to unlock the collateral
        //flashRepay(lendingPool, kovanLink, borrowAmt);
 
        // withdraws the AAVE, DAI and LINK collateral from the lending pool
        flashWithdraw(lendingPool, amounts[0]);
        
        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        // // Transfer the specified amount of DAI to this contract.        
        // TransferHelper.safeTransferFrom(kovanDai, msg.sender, address(this), amounts[0]);
        // // Approve the router to spend DAI.        
        // TransferHelper.safeApprove(kovanDai, address(swapRouter), amounts[0]);
        // // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.       
        // // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.       
        // ISwapRouter.ExactInputSingleParams memory paramsSwap = 
        //     ISwapRouter.ExactInputSingleParams({
        //         tokenIn: kovanDai,
        //         tokenOut: kovanADai,
        //         fee: poolFee,
        //         recipient: msg.sender,
        //         deadline: block.timestamp,
        //         amountIn: amounts[0],
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     });
        // // The call to `exactInputSingle` executes the swap.        
        // uint256 amountOut = swapRouter.exactInputSingle(paramsSwap);
        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        
        // Approve the LendingPool contract allowance to *pull* the owed amount
        // i.e. AAVE V2's way of repaying the flash loan
        for (uint i = 0; i < assets.length; i++) {
            uint amountOwing = amounts[i].add(premiums[i]);
            IERC20(assets[i]).approve(address(_lendingPool), amountOwing);
        }
    
        return true;
    }

    /*
    * Deposits the flashed AAVE, DAI and LINK liquidity onto the lending pool as collateral
    */
    function flashDeposit(ILendingPool _lendingPool, uint256 _amount) internal {
        // approve lending pool
        IERC20(kovanDai).approve(lendingPoolAddr, _amount);
        // deposit the flashed AAVE, DAI and LINK as collateral
        _lendingPool.deposit(kovanDai, _amount, address(this), uint16(0));
        
    }

    /*
    * Withdraws the AAVE, DAI and LINK collateral from the lending pool
    */
    function flashWithdraw(ILendingPool _lendingPool, uint256 _amount) internal {
        _lendingPool.withdraw(kovanDai, _amount, address(this));
    }
    
    /*
    * Borrows _borrowAmt amount of _borrowAsset based on the existing deposited collateral
    */
    function flashBorrow(ILendingPool _lendingPool, address _borrowAsset, uint256 _borrowAmt) internal {
        
        // borrowing x asset at stable rate, no referral, for yourself
        _lendingPool.borrow(
            _borrowAsset, 
            _borrowAmt, 
            1, 
            uint16(0), 
            address(this)
        );
        
    }

    /*
    * Repays _repayAmt amount of _repayAsset
    */
    function flashRepay(ILendingPool _lendingPool, address _repayAsset, uint256 _repayAmt) internal {
        
        // approve the repayment from this contract
        IERC20(_repayAsset).approve(lendingPoolAddr, _repayAmt);
        
        _lendingPool.repay(
            _repayAsset, 
            _repayAmt, 
            1, 
            address(this)
        );
    }

    /*
    * Repays _repayAmt amount of _repayAsset
    */
    function flashSwapBorrowRate(ILendingPool _lendingPool, address _asset, uint256 _rateMode) internal {
        
        _lendingPool.swapBorrowRateMode(_asset, _rateMode);
        
    }
    
    /*
    * This function is manually called to commence the flash loans sequence
    */
    function executeFlashLoans(uint256 _amout) public onlyOwner {
        address receiverAddress = address(this);
        
        _amout = _amout*1e18;

        // the various assets to be flashed
        address[] memory assets = new address[](1);
        assets[0] = kovanDai;
        
        // the amount to be flashed for each asset
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amout;
        
        // 0 = no debt, 1 = stable, 2 = variable
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        
        amount = _amout;
        
        address onBehalfOf = address(this);
        bytes memory params = "";
        uint16 referralCode = 0;

        _lendingPool.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }

    function showAddress() public view returns(address _provider, address _swapRouter){
        return (address(provider), address(swapRouter));
    }
        
    /*
    * Rugpull all ERC20 tokens from the contract
    */
    function rugPull() public payable onlyOwner {
        
        // withdraw all ETH
        msg.sender.call{ value: address(this).balance }("");
        
        // withdraw all x ERC20 tokens
        IERC20(kovanAave).transfer(msg.sender, IERC20(kovanAave).balanceOf(address(this)));
        IERC20(kovanDai).transfer(msg.sender, IERC20(kovanDai).balanceOf(address(this)));
        IERC20(kovanLink).transfer(msg.sender, IERC20(kovanLink).balanceOf(address(this)));
    }
    
}