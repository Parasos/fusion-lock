// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.24;

using stdStorage for StdStorage;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {stdStorage, StdStorage, Test, console} from "forge-std/Test.sol";
import {FusionLock, BridgeInterface} from "../src/FusionLock.sol";
import {Utilities} from "./Utilities.sol";

contract ArbitaryErc20 is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, address owner) ERC20(name_, symbol_) Ownable(owner) {}

    function sudoMint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

// Dummy Bridge contract
contract Bridge is BridgeInterface {
    using SafeERC20 for IERC20;

    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32, /* _minGasLimit */
        bytes calldata /* _extraData */
    ) external {
        // lock l1 token with bridge
        IERC20(_l1Token).safeTransferFrom(msg.sender, address(this), _amount);

        // mint l2 token to receiver
        ArbitaryErc20(_l2Token).sudoMint(_to, _amount);
    }

    function depositETHTo(address _to, uint32, /* _minGasLimit */ bytes calldata /* _extraData */ ) external payable {
        // transfer eth to receiver
        payable(_to).transfer(msg.value);
    }
}

contract FusionLockTest is FusionLock, Test {
    ArbitaryErc20 token1 = new ArbitaryErc20("Wrapped tBTC", "tBTC", msg.sender);

    Utilities internal utils;
    Bridge public bridge;

    uint32 constant MIN_GAS_LIMIT = 20000;
    address internal alice;
    address internal bob;
    address payable[] internal users;
    address internal sudoOwner = address(0x1234567890123456789012345678901234567890);
    address[] singleToken = new address[](1);

    address[] initialAllowToken = [address(token1)];

    // WITHDRAWAL_START_TIME = Tue Mar 12 2024 18:30:00 GMT+0000
    uint256 public constant WITHDRAWAL_START_TIME = 1710268200;

    constructor() FusionLock(WITHDRAWAL_START_TIME, initialAllowToken, sudoOwner) {}

    function setUp() public {
        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        vm.label(alice, "Alice");
        bob = users[1];
        vm.label(bob, "Bob");

        // deploy bridge
        bridge = new Bridge();

        // set bridge address
        setBridgeAddress();

        // set l2 token
        ArbitaryErc20 l2Token = new ArbitaryErc20("Wrapped tBTC L2", "tBTC", bridgeProxyAddress);

        TokenAddressPair[] memory tokenPairs = new TokenAddressPair[](1);
        tokenPairs[0] = TokenAddressPair(address(token1), address(l2Token));
        this.changeMultipleL2TokenAddresses(tokenPairs);
        // initially contract shouldn't hold any eth, required for test cases assertions
        vm.deal(address(this), 0 ether);
    }

    // helper function to create multiple erc20 tokens
    function createErc20Tokens(uint256 numberOfTokens, string memory symbol) public returns (ArbitaryErc20[] memory) {
        ArbitaryErc20[] memory listErc20Tokens = new ArbitaryErc20[](numberOfTokens);

        for (uint256 i = 0; i < numberOfTokens; i++) {
            vm.startPrank(sudoOwner);
            string memory l1TokenName = string(abi.encodePacked("L1Token", Strings.toString(i + 1)));
            listErc20Tokens[i] = new ArbitaryErc20(l1TokenName, symbol, sudoOwner);

            string memory l2TokenName = string(abi.encodePacked("L2Token", Strings.toString(i + 1)));
            // keep owner of L2 token as bridge address
            ArbitaryErc20 l2Token = new ArbitaryErc20(l2TokenName, symbol, bridgeProxyAddress);

            this.allow(address(listErc20Tokens[i]), address(l2Token));

            vm.stopPrank();
        }
        return listErc20Tokens;
    }

    // Deposit with single user
    // Deposit for varying amounts
    // Deposit multiple erc20 tokens single time
    function test_DepositsWithVaryingAmountsAndMultipleErc20Tokens(uint256 amount, uint256 numberOfTokens)
        public
        returns (ArbitaryErc20[] memory)
    {
        vm.assume(numberOfTokens < 100);
        vm.assume(amount > 0);
        ArbitaryErc20[] memory tokens = createErc20Tokens(numberOfTokens, "Token");
        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            // mint to alice address
            vm.startPrank(sudoOwner);
            tokens[tokenId].sudoMint(alice, amount);
            vm.stopPrank();

            vm.startPrank(alice);

            // approve spending token
            tokens[tokenId].approve(address(this), amount);
            assertEq(tokens[tokenId].balanceOf(alice), amount);

            vm.expectEmit();
            emit Deposit(alice, address(tokens[tokenId]), amount, block.timestamp);
            this.depositERC20(address(tokens[tokenId]), amount);

            // alice balance consumed
            assertEq(tokens[tokenId].balanceOf(alice), 0);

            // contract balance updated
            assertEq(tokens[tokenId].balanceOf(address(this)), amount);

            // user storage updated
            uint256 depositAmount = this.getDepositAmount(alice, address(tokens[tokenId]));
            assertEq(depositAmount, amount);

            vm.stopPrank();
        }
        return tokens;
    }

    // Deposit with single user
    // Deposit varying amounts
    // Deposit single erc20 tokens multiple times
    function test_ReDepositErc20WithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        vm.assume(amount > 0);
        vm.assume(numberOfDeposits < 1000 && numberOfDeposits > 0);
        for (uint256 depositId = 0; depositId < numberOfDeposits; depositId++) {
            // don't overflow total supply
            vm.assume(type(uint256).max - token1.totalSupply() > amount);

            vm.startPrank(msg.sender);
            // mint to alice address
            token1.sudoMint(alice, amount);
            vm.startPrank(alice);

            // approve spending token
            token1.approve(address(this), amount);
            assertEq(token1.balanceOf(alice), amount);

            // deposit token
            vm.expectEmit();
            emit Deposit(alice, address(token1), amount, block.timestamp);
            this.depositERC20(address(token1), amount);

            // alice balance consumed
            assertEq(token1.balanceOf(alice), 0);
            vm.stopPrank();
        }
        // contract balance updated
        assertEq(token1.balanceOf(address(this)), amount * numberOfDeposits);

        // user storage updated
        uint256 depositAmount = this.getDepositAmount(alice, address(token1));
        assertEq(depositAmount, amount * numberOfDeposits);
    }

    // Deposit with multiple user once
    // Deposit varying amounts
    // Deposit single erc20 tokens
    function test_DepositErc20WithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        vm.assume(amount > 0);
        vm.assume(numberOfUsers < 100);
        users = utils.createUsers(numberOfUsers);

        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            // don't overflow total supply
            vm.assume(type(uint256).max - token1.totalSupply() > amount);

            address depositCaller = users[userId];

            vm.startPrank(msg.sender);
            token1.sudoMint(depositCaller, amount);
            vm.startPrank(depositCaller);

            // approve spending token
            token1.approve(address(this), amount);
            assertEq(token1.balanceOf(depositCaller), amount);

            vm.expectEmit();
            emit Deposit(depositCaller, address(token1), amount, block.timestamp);
            this.depositERC20(address(token1), amount);

            // user balance consumed
            assertEq(token1.balanceOf(depositCaller), 0);

            // user storage updated
            uint256 depositAmount = this.getDepositAmount(depositCaller, address(token1));
            assertEq(depositAmount, amount);

            vm.stopPrank();
        }
        // contract balance updated
        assertEq(token1.balanceOf(address(this)), amount * numberOfUsers);
    }

    // Deposit with single user multiple time
    // Deposit same amount multiple times
    function test_ReDepositEthWithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        vm.assume(amount > 0);
        // max amount of eth in supply
        vm.assume(amount < 18000000000000000000);
        vm.assume(numberOfDeposits < 1000 && numberOfDeposits > 0);
        for (uint256 depositId = 0; depositId < numberOfDeposits; depositId++) {
            vm.startPrank(alice);
            // set balance for alice
            vm.deal(alice, amount);

            vm.expectEmit();
            emit Deposit(alice, address(0x00), amount, block.timestamp);
            this.depositEth{value: amount}();

            // alice balance consumed
            assertEq(alice.balance, 0);
            vm.stopPrank();
        }
        // contract balance updated
        assertEq(this.getEthBalance(), numberOfDeposits * amount);

        // alice storage updated
        uint256 depositAmount = this.getDepositAmount(alice, ETH_TOKEN_ADDRESS);
        assertEq(depositAmount, amount * numberOfDeposits);
    }

    // Deposit for multiple users
    // Deposit once per user
    function test_DepositEthWithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        vm.assume(amount > 0);
        // max amount of eth in supply
        vm.assume(amount < 18000000000000000000);
        vm.assume(numberOfUsers < 100);
        users = utils.createUsers(numberOfUsers);

        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            address depositCaller = users[userId];

            vm.startPrank(depositCaller);
            // set balance for user
            vm.deal(depositCaller, amount);

            vm.expectEmit();
            emit Deposit(depositCaller, address(0x00), amount, block.timestamp);
            this.depositEth{value: amount}();

            // user balance consumed
            assertEq(address(depositCaller).balance, 0);

            // user storage updated
            uint256 depositAmount = this.getDepositAmount(depositCaller, ETH_TOKEN_ADDRESS);
            assertEq(depositAmount, amount);

            vm.stopPrank();
        }
        // contract balance updated
        assertEq(this.getEthBalance(), numberOfUsers * amount);
    }

    // helper function to pause contract
    function pauseContract() public {
        vm.startPrank(sudoOwner);
        this.pause();
        vm.stopPrank();
    }

    // helper function to unpause contract
    function unPauseContract() public {
        vm.startPrank(sudoOwner);
        this.unpause();
        vm.stopPrank();
    }

    function test_DepositNotAllowedWhenContractFunctionalityPaused() public {
        pauseContract();
        vm.startPrank(msg.sender);
        token1.sudoMint(alice, 100);
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        bool success;

        token1.approve(alice, 100);
        (success,) = address(this).call(abi.encodeWithSignature("depositERC20(address, uint256)", address(token1), 100));
        assertFalse(success);
        assertEq(token1.balanceOf(alice), 100);

        (success,) = address(this).call(abi.encodeWithSignature("depositEth()", 1 ether));
        assertFalse(success);
        assertEq(address(alice).balance, 1 ether);

        // now unpause the contract
        unPauseContract();

        aliceDepositEth(1 ether);
        aliceDepositErc20(100);
    }

    function test_DepositNotAllowedWhenWithdrawStarts(uint256 endTime) public {
        vm.assume(endTime > withdrawalStartTime);
        vm.warp(endTime);
        vm.startPrank(alice);
        vm.expectRevert("Deposit time already ended");
        this.depositERC20(address(token1), 100);
        vm.expectRevert("Deposit time already ended");
        this.depositEth{value: 100}();
    }

    function test_DepositNotAllowedForAmountZero() public {
        vm.startPrank(alice);
        vm.expectRevert("Amount Should Be Greater Than Zero");
        this.depositERC20(address(token1), 0);
        vm.expectRevert("Amount Should Be Greater Than Zero");
        this.depositEth{value: 0}();
    }

    function test_DepositNotAllowedForNonAllowListedToken() public {
        vm.startPrank(alice);
        ArbitaryErc20 notAllowListedToken = new ArbitaryErc20("Dummy Token", "DTOK", msg.sender);
        vm.expectRevert("Deposit token not allowed");
        this.depositERC20(address(notAllowListedToken), 100);
    }

    function test_DepositErc20WhenApproveLessAmount() public {
        vm.startPrank(msg.sender);
        token1.sudoMint(alice, 100);
        vm.startPrank(alice);
        token1.approve(alice, 50);
        (bool success,) =
            address(this).call(abi.encodeWithSignature("depositERC20(address, uint256)", address(token1), 100));
        // ERC20InsufficientAllowance
        assertFalse(success);

        assertEq(token1.balanceOf(alice), 100);
        assertEq(token1.balanceOf(address(this)), 0);

        // alice storage not updated
        uint256 depositAmount = this.getDepositAmount(alice, address(token1));
        assertEq(depositAmount, 0);
    }

    function test_DepositEthWhenInsufficientBalance() public {
        vm.startPrank(alice);
        vm.deal(alice, 1 ether);
        (bool success,) = address(this).call(abi.encodeWithSignature("depositEth()", 2 ether));
        // Deposit should revert
        assertFalse(success);
        assertEq(address(alice).balance, 1 ether);
        assertEq(this.getEthBalance(), 0);

        // alice storage not updated
        uint256 depositAmount = this.getDepositAmount(alice, ETH_TOKEN_ADDRESS);
        assertEq(depositAmount, 0);
    }

    // Withdraw To L1
    // single user
    // multiple tokens
    function test_WithdrawToL1WithVaryingAmountsAndMultipleErc20Tokens(uint256 amount, uint256 numberOfTokens) public {
        ArbitaryErc20[] memory tokens = test_DepositsWithVaryingAmountsAndMultipleErc20Tokens(amount, numberOfTokens);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        // create list of addresses
        address[] memory listOfTokens = new address[](numberOfTokens);
        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            listOfTokens[tokenId] = address(tokens[tokenId]);
        }

        vm.startPrank(alice);
        this.withdrawDepositsToL1(listOfTokens);

        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            // user gets back his lock balance
            assertEq(ArbitaryErc20(address(tokens[tokenId])).balanceOf(alice), amount);

            // contract token balance back to zero, after unlocking all deposits for specific token
            assertEq(ArbitaryErc20(address(tokens[tokenId])).balanceOf(address(this)), 0);

            // use withdraw amount updated
            uint256 userDepositAmount = this.getDepositAmount(alice, address(tokens[tokenId]));
            assertEq(userDepositAmount, 0);

            vm.stopPrank();
        }
    }

    // Bridge all tokens to L2
    function test_WithdrawToL2WithVaryingAmountsAndMultipleErc20Tokens(uint256 amount, uint256 numberOfTokens) public {
        ArbitaryErc20[] memory l1Tokens = test_DepositsWithVaryingAmountsAndMultipleErc20Tokens(amount, numberOfTokens);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        // create list of addresses
        address[] memory listOfTokens = new address[](numberOfTokens);
        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            listOfTokens[tokenId] = address(l1Tokens[tokenId]);
        }

        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            vm.expectEmit();
            emit WithdrawToL2(
                alice, address(l1Tokens[tokenId]), allowedTokens[address(l1Tokens[tokenId])].l2TokenAddress, amount
            );
        }

        // withdraw all tokens deposited by alice
        vm.startPrank(alice);
        this.withdrawDepositsToL2(listOfTokens, MIN_GAS_LIMIT);

        // assert balances
        for (uint256 tokenId = 0; tokenId < numberOfTokens; tokenId++) {
            address l2Token = allowedTokens[address(l1Tokens[tokenId])].l2TokenAddress;

            // alice balance
            assertEq(l1Tokens[tokenId].balanceOf(alice), 0);
            assertEq(ArbitaryErc20(address(l2Token)).balanceOf(alice), amount);

            // FusionLock balance
            assertEq(l1Tokens[tokenId].balanceOf(address(this)), 0);
            assertEq(ArbitaryErc20(address(l2Token)).balanceOf(address(this)), 0);

            // bridge balance
            assertEq(l1Tokens[tokenId].balanceOf(bridgeProxyAddress), amount);
            assertEq(ArbitaryErc20(address(l2Token)).balanceOf(bridgeProxyAddress), 0);
        }
    }

    // Withdraw to L1
    // single user
    // single token
    // done multiple deposits
    function test_MultipleWithdrawToL1Erc20WithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        test_ReDepositErc20WithVaryingAmounts(amount, numberOfDeposits);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        vm.startPrank(alice);
        vm.expectEmit();
        singleToken[0] = address(token1);
        emit WithdrawToL1(alice, address(token1), numberOfDeposits * amount);
        this.withdrawDepositsToL1(singleToken);

        // alice gets back her locked balance
        assertEq(token1.balanceOf(alice), amount * numberOfDeposits);

        // contract balance back to zero, after unlocking all deposits
        assertEq(token1.balanceOf(address(this)), 0);
    }

    // bridge to L2
    // single user
    // single token
    // done multiple deposits
    function test_MultipleWithdrawToL2Erc20WithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        test_ReDepositErc20WithVaryingAmounts(amount, numberOfDeposits);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        address l2Token = allowedTokens[address(token1)].l2TokenAddress;

        vm.startPrank(alice);
        vm.expectEmit();
        emit WithdrawToL2(alice, address(token1), l2Token, numberOfDeposits * amount);

        // create list of addresses
        singleToken[0] = address(address(token1));
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

        // alice gets l2 token minted
        assertEq(ArbitaryErc20(l2Token).balanceOf(alice), amount * numberOfDeposits);
        assertEq(token1.balanceOf(alice), 0);

        // FusionLock transfers l1 token
        assertEq(ArbitaryErc20(l2Token).balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        // Bridge gets l1 token
        assertEq(ArbitaryErc20(l2Token).balanceOf(bridgeProxyAddress), 0);
        assertEq(token1.balanceOf(bridgeProxyAddress), amount * numberOfDeposits);
    }

    // Withdraw to L1
    // multiple users
    // single token
    function test_WithdrawToL1Erc20WithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        test_DepositErc20WithMultipleDepositOwners(amount, numberOfUsers);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        singleToken[0] = address(token1);

        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            // get user
            address withdrawCaller = users[userId];
            vm.startPrank(withdrawCaller);

            // withdraw
            vm.expectEmit();
            emit WithdrawToL1(withdrawCaller, address(token1), amount);
            this.withdrawDepositsToL1(singleToken);

            // users balance updated
            assertEq(token1.balanceOf(withdrawCaller), amount);
        }
        assertEq(token1.balanceOf(address(this)), 0);
    }

    // Bridge to L2
    // multiple users
    // single token
    function test_WithdrawToL2Erc20WithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        test_DepositErc20WithMultipleDepositOwners(amount, numberOfUsers);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        singleToken[0] = address(address(token1));
        address l2Token = allowedTokens[address(token1)].l2TokenAddress;

        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            // get user
            address withdrawCaller = users[userId];
            vm.startPrank(withdrawCaller);

            // withdraw
            vm.expectEmit();
            emit WithdrawToL2(withdrawCaller, address(token1), l2Token, amount);
            this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

            // users gets l2 token minted
            assertEq(ArbitaryErc20(l2Token).balanceOf(withdrawCaller), amount);
            assertEq(token1.balanceOf(withdrawCaller), 0);
        }

        // FusionLock transfers all l1 token
        assertEq(ArbitaryErc20(l2Token).balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        // Bridge gets l1 token
        assertEq(ArbitaryErc20(l2Token).balanceOf(bridgeProxyAddress), 0);
        assertEq(token1.balanceOf(bridgeProxyAddress), amount * numberOfUsers);
    }

    // Withdraw Eth to l1
    // single withdrawal after multiple deposits done
    function test_MultipleWithdrawToL1EthWithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        test_ReDepositEthWithVaryingAmounts(amount, numberOfDeposits);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        vm.startPrank(alice);
        vm.expectEmit();
        emit WithdrawToL1(alice, ETH_TOKEN_ADDRESS, numberOfDeposits * amount);
        singleToken[0] = ETH_TOKEN_ADDRESS;
        this.withdrawDepositsToL1(singleToken);

        // user unlocks all his balance
        assertEq(alice.balance, amount * numberOfDeposits);
        // contract balance back to zero after processing all withdraws
        assertEq(address(this).balance, 0);
    }

    // Bridge Eth to l2
    // single withdrawal multiple deposits done
    function test_MultipleWithdrawToL2EthWithVaryingAmounts(uint256 amount, uint256 numberOfDeposits) public {
        test_ReDepositEthWithVaryingAmounts(amount, numberOfDeposits);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        singleToken[0] = address(ETH_TOKEN_ADDRESS);

        vm.startPrank(alice);
        vm.expectEmit();
        emit WithdrawToL2(alice, ETH_TOKEN_ADDRESS, ETH_TOKEN_ADDRESS, numberOfDeposits * amount);
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

        // alice gets all his locked balance
        assertEq(alice.balance, amount * numberOfDeposits);

        // FusionLock balance back to zero after bridging
        assertEq(address(this).balance, 0);

        // Bridge balance set to zero after giving back tokens to sender
        assertEq(bridgeProxyAddress.balance, 0);
    }

    // Withdraw To L1
    // single withdrawal for each user
    function test_WithdrawToL1EthWithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        test_DepositEthWithMultipleDepositOwners(amount, numberOfUsers);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        singleToken[0] = address(ETH_TOKEN_ADDRESS);
        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            // get user
            address withdrawCaller = users[userId];
            vm.startPrank(withdrawCaller);

            // expected event
            vm.expectEmit();
            emit WithdrawToL1(withdrawCaller, ETH_TOKEN_ADDRESS, amount);
            this.withdrawDepositsToL1(singleToken);

            // user unlocks his balance
            assertEq(withdrawCaller.balance, amount);

            vm.stopPrank();
        }
        // contract balance back to zero after processing all withdraws
        assertEq(address(this).balance, 0);
    }

    // Bridge To L2
    // single withdrawal for each user
    function test_WithdrawToL2EthWithMultipleDepositOwners(uint256 amount, uint256 numberOfUsers) public {
        test_DepositEthWithMultipleDepositOwners(amount, numberOfUsers);
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        singleToken[0] = address(ETH_TOKEN_ADDRESS);

        for (uint256 userId = 0; userId < numberOfUsers; userId++) {
            // get user
            address withdrawCaller = users[userId];
            vm.startPrank(withdrawCaller);

            // expected event
            vm.expectEmit();
            emit WithdrawToL2(withdrawCaller, ETH_TOKEN_ADDRESS, ETH_TOKEN_ADDRESS, amount);
            this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

            // user gets his balance through bridge
            assertEq(withdrawCaller.balance, amount);

            vm.stopPrank();
        }
        // FusionLock balance back to zero after bridging
        assertEq(address(this).balance, 0);

        // Bridge balance set to zero after giving back tokens to sender
        assertEq(bridgeProxyAddress.balance, 0);
    }

    // helper method to set bridge address
    function setBridgeAddress() public {
        vm.startPrank(sudoOwner);
        // set bridge address
        vm.expectEmit();
        emit BridgeAddress(address(bridge));
        this.setBridgeProxyAddress(address(bridge));
    }

    // helper method to deposit erc20 on behalf of alice
    function aliceDepositErc20(uint256 amount) public {
        vm.startPrank(msg.sender);
        token1.sudoMint(alice, amount);
        vm.startPrank(alice);
        token1.approve(address(this), amount);
        this.depositERC20(address(token1), amount);
    }

    // helper method to deposit eth on behalf of alice
    function aliceDepositEth(uint256 amount) public {
        vm.startPrank(alice);
        vm.deal(alice, amount);
        this.depositEth{value: amount}();
    }

    // helper method to withdraw erc20 on behalf of deposit owner
    function aliceWithdrawErc20OnL1() public {
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        vm.startPrank(alice);
        singleToken[0] = address(token1);
        this.withdrawDepositsToL1(singleToken);
    }

    // helper method to withdraw eth on behalf of deposit owner
    function aliceWithdrawEthOnL1() public {
        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        vm.startPrank(alice);
        singleToken[0] = ETH_TOKEN_ADDRESS;
        this.withdrawDepositsToL1(singleToken);
    }

    // helper method to bridge erc20 on behalf of deposit owner
    function aliceWithdrawErc20OnL2() public {
        vm.warp(this.withdrawalStartTime());
        vm.startPrank(alice);
        singleToken[0] = address(token1);
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);
    }

    // helper method to bridge eth on behalf of deposit owner
    function aliceWithdrawEthOnL2() public {
        vm.warp(this.withdrawalStartTime());
        vm.startPrank(alice);
        singleToken[0] = address(ETH_TOKEN_ADDRESS);
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);
    }

    function test_WithdrawNotAllowedWhenFunctionalityPaused() public {
        aliceDepositEth(1 ether);
        pauseContract();

        vm.startPrank(alice);
        bool success;

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        singleToken[0] = ETH_TOKEN_ADDRESS;

        (success,) = address(vm).call(abi.encodeWithSignature("address[]", singleToken));
        assertFalse(success);
        assertEq(alice.balance, 0 ether);

        (success,) = address(vm).call(
            abi.encodeWithSignature("withdrawAllDepositsToL2(address[], uint32)", singleToken, MIN_GAS_LIMIT)
        );
        assertFalse(success);
        assertEq(alice.balance, 0 ether);
    }

    function test_TryToWithdrawWhenDepositNotDone() public {
        aliceDepositErc20(100);
        aliceDepositEth(100);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        singleToken[0] = address(token1);
        vm.startPrank(bob);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL1(singleToken);

        singleToken[0] = ETH_TOKEN_ADDRESS;
        vm.startPrank(bob);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL1(singleToken);

        singleToken[0] = ETH_TOKEN_ADDRESS;
        vm.startPrank(bob);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

        singleToken[0] = address(token1);
        vm.startPrank(bob);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);
    }

    function test_TryReWithdrawalForL1() public {
        aliceDepositErc20(100);
        aliceDepositEth(100);

        aliceWithdrawErc20OnL1();
        singleToken[0] = address(token1);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL1(singleToken);

        aliceWithdrawEthOnL1();
        singleToken[0] = ETH_TOKEN_ADDRESS;
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL1(singleToken);
    }

    function test_TryReBridgingForL2() public {
        aliceDepositErc20(100);
        aliceDepositEth(100);

        aliceWithdrawErc20OnL2();
        singleToken[0] = address(token1);
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);

        aliceWithdrawEthOnL2();
        singleToken[0] = ETH_TOKEN_ADDRESS;
        vm.expectRevert("Withdrawal completed or token never deposited");
        this.withdrawDepositsToL2(singleToken, MIN_GAS_LIMIT);
    }

    function test_TryWithdrawForL1AtVaryingTimes() public {
        // Alice deposits ERC20 tokens and Eth
        aliceDepositErc20(100);
        aliceDepositEth(100);

        // Attempt to withdraw n-1 timestamp before release if n is release time
        vm.warp(this.withdrawalStartTime() - 1);
        vm.expectRevert("Withdrawal not started");
        singleToken[0] = address(token1);
        this.withdrawDepositsToL1(singleToken);
        vm.expectRevert("Withdrawal not started");
        singleToken[0] = ETH_TOKEN_ADDRESS;
        this.withdrawDepositsToL1(singleToken);
        assertFalse(this.isWithdrawalTimeStarted());

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());

        assertTrue(this.isWithdrawalTimeStarted());

        singleToken[0] = ETH_TOKEN_ADDRESS;
        this.withdrawDepositsToL1(singleToken);
        singleToken[0] = address(token1);
        this.withdrawDepositsToL1(singleToken);
    }

    function test_TryWithdrawForL2AtVaryingTimes() public {
        // Alice deposits ERC20 tokens and Eth
        aliceDepositErc20(100);
        aliceDepositEth(100);

        address[] memory listOfTokens = new address[](2);
        listOfTokens[0] = ETH_TOKEN_ADDRESS;
        listOfTokens[1] = address(token1);

        // Attempt to withdraw before start time
        vm.warp(this.withdrawalStartTime() - 1);
        vm.expectRevert("Withdrawal not started");
        this.withdrawDepositsToL2(listOfTokens, MIN_GAS_LIMIT);

        // set time to release all deposits
        vm.warp(this.withdrawalStartTime());
        this.withdrawDepositsToL2(listOfTokens, MIN_GAS_LIMIT);
    }

    function test_AllowNewToken() public {
        vm.startPrank(sudoOwner);
        ArbitaryErc20 newToken = new ArbitaryErc20("Token X", "TokX", msg.sender);
        assertFalse(this.getTokenInfo(address(newToken)).isAllowed);
        this.allow(address(newToken), address(0x00));
        assertTrue(this.getTokenInfo(address(newToken)).isAllowed);
    }

    function test_TryToAllowTokenAfterWithdrawalStarts() public {
        vm.startPrank(sudoOwner);
        vm.warp(this.withdrawalStartTime());
        ArbitaryErc20 newToken = new ArbitaryErc20("Token X", "TokX", msg.sender);
        vm.expectRevert("Withdrawal has started, token allowance cannot be modified");
        this.allow(address(newToken), address(0x00));
    }

    function test_TryToChangeWithdrawalTimeAtDifferentIntervals() public {
        vm.startPrank(sudoOwner);
        vm.warp(this.withdrawalStartTime());

        uint256 setEndTime = this.withdrawalStartTime() + 30 days;
        vm.expectRevert("Withdrawal start time can only be decreased, not increased");
        // withdrawal started
        this.changeWithdrawalTime(setEndTime);

        vm.warp(this.withdrawalStartTime() - 1);
        setEndTime = this.withdrawalStartTime() - 1 days;
        vm.expectRevert("New timestamp can't be historical");
        this.changeWithdrawalTime(setEndTime);

        vm.warp(this.withdrawalStartTime() - 1);
        uint256 endTime = this.withdrawalStartTime() + 1;
        vm.expectRevert("Withdrawal start time can only be decreased, not increased");
        this.changeWithdrawalTime(endTime);
    }

    function test_FallbackShouldRevert() public {
        // Attempt to send ether to the contract and expect it to revert
        (bool success,) = address(this).call{value: 1 ether}("");
        assertFalse(success, "Fallback function should revert");
    }

    function test_ReceiveShouldRevert() public {
        // Attempt to call receive function and expect it to revert
        (bool success,) = address(this).call{value: 1 ether}(abi.encodeWithSignature("receive()"));
        assertFalse(success, "Receive function should revert");
    }

    function test_ChangeL2TokenAddressWhenL1TokenNotAllowed() public {
        ArbitaryErc20 notAllowedL1Token = new ArbitaryErc20("Wrapped Eth", "Eth", msg.sender);
        ArbitaryErc20 l2Token = new ArbitaryErc20("Wrapped L2 Eth", "L2Eth", msg.sender);
        TokenAddressPair[] memory tokenPairs = new TokenAddressPair[](1);
        tokenPairs[0] = TokenAddressPair(address(notAllowedL1Token), address(l2Token));

        // Expect revert with the given message when trying to change the L2 token address for an L1 token that is not allowed
        vm.expectRevert("Need to allow token before changing L2 address");
        this.changeMultipleL2TokenAddresses(tokenPairs);
    }

    function test_CallOwnerFunctionsWithNonOwner() public {
        bool success;
        vm.startPrank(alice);

        (success,) = address(vm).call(abi.encodeWithSignature("allow(address)", address(0x00)));
        assertFalse(success);

        uint256 newEndTime = this.withdrawalStartTime() + 10 days;
        (success,) = address(vm).call(abi.encodeWithSignature("changeWithdrawalTime(uint256)", newEndTime));
        assertFalse(success);

        (success,) = address(vm).call(abi.encodeWithSignature("pause()", true));
        assertFalse(success);

        (success,) = address(vm).call(abi.encodeWithSignature("unpause()", true));
        assertFalse(success);

        TokenAddressPair[] memory tokenPairs = new TokenAddressPair[](1);
        tokenPairs[0] = TokenAddressPair(address(token1), address(token1));
        (success,) =
            address(vm).call(abi.encodeWithSignature("changeMultipleL2TokenAddresses(TokenAddressPair[])", tokenPairs));
        assertFalse(success);
    }
}
