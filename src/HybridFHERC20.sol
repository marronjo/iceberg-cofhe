// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FHE, InEuint128, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

/**
 * @dev Minimal implementation of an FHERC20 token
 * Implementation of the bare minimum methods to make
 * the hook work with a hybrid FHE / ERC20 token
 */
contract HybridFHERC20 is ERC20 {

    //errors
    error HybridFHERC20__InvalidSender(address sender);
    error HybridFHERC20__InvalidReceiver(address receiver);

    //allow for more natural syntax for euint types
    using FHE for uint256;

    //encrypted balances
    mapping(address => euint128) public encBalances;
    euint128 internal totalEncryptedSupply = FHE.asEuint128(0);

    //zero constant
    euint128 private immutable ZERO = FHE.asEuint128(0);
    uint256 private immutable TIMEOUT = 100;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    // ----------- Public Mint Functions --------------------
    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    // ----------- Public Burn Functions --------------------
    function burn(address user, uint256 amount) public {
        _burn(user, amount);
    }

    // ----------- Encrypted Mint Functions -----------------
    function mintEncrypted(address user, InEuint128 memory amount) public {
        _mintEnc(user, FHE.asEuint128(amount));
    }

    function mintEncrypted(address user, euint128 amount) public {
        _mintEnc(user, amount);
    }

    function _mintEnc(address user, euint128 amount) internal {
        encBalances[user] = encBalances[user].add(amount);
        totalEncryptedSupply = totalEncryptedSupply.add(amount);

        FHE.allowThis(encBalances[user]);
        FHE.allow(encBalances[user], user);
        FHE.allowGlobal(totalEncryptedSupply);
    }

    // ----------- Encrypted Burn Functions -----------------
    function burnEncrypted(address user, InEuint128 memory amount) public {
        _burnEnc(user, FHE.asEuint128(amount));
    }

    function burnEncrypted(address user, euint128 amount) public {
        _burnEnc(user, amount);
    }

    function _burnEnc(address user, euint128 amount) internal {
        euint128 burnAmount = _calculateBurnAmount(user, amount);
        encBalances[user] = encBalances[user].sub(burnAmount);
        totalEncryptedSupply = totalEncryptedSupply.sub(burnAmount);

        FHE.allowThis(encBalances[user]);
        FHE.allow(encBalances[user], user);
        FHE.allowGlobal(totalEncryptedSupply);
    }

    function _calculateBurnAmount(address user, euint128 amount) internal returns(euint128){
        return FHE.select(amount.lte(encBalances[user]), amount, ZERO);
    }

    // ----------- Encrypted Transfer Functions ---------------
    function transferFromEncrypted(address from, address to, InEuint128 memory amount) external returns(euint128) {
        return _transferImpl(from, to, FHE.asEuint128(amount));
    }

    function transferFromEncrypted(address from, address to, euint128 amount) external returns(euint128) {
        return _transferImpl(from, to, amount);
    }

    function _transferImpl(address from, address to, euint128 amount) internal returns (euint128) {
        //ensure sender / receiver is not 0x00
        if(from == address(0)){
            revert HybridFHERC20__InvalidSender(address(0));
        }
        if(to == address(0)){
            revert HybridFHERC20__InvalidReceiver(address(0));
        }

        // Make sure the sender has enough tokens.
        euint128 amountToSend = FHE.select(amount.lte(encBalances[from]), amount, ZERO);

        // Add to the balance of `to` and subract from the balance of `from`.
        encBalances[to] = encBalances[to].add(amountToSend);
        encBalances[from] = encBalances[from].sub(amountToSend);

        //allow contract to interact with balances
        FHE.allowThis(encBalances[to]);
        FHE.allowThis(encBalances[from]);

        //allow users to interact with their balances
        FHE.allow(encBalances[to], to);
        FHE.allow(encBalances[from], from);

        return amountToSend;
    }

    // --------- Decrypt Balance Functions ------------------
    function decryptBalance(address user) public {
        FHE.decrypt(encBalances[user]);
    }

    function getDecryptBalanceResult(address user) public view returns(uint128) {
        return FHE.getDecryptResult(encBalances[user]);
    }

    function getDecryptBalanceResultSafe(address user) public view returns(uint128, bool) {
        return FHE.getDecryptResultSafe(encBalances[user]);
    }

    // --------- Encrypted Wrapping Functions ---------------
    function wrap(address user, uint128 amount) external {
        _wrap(user, amount);
    }

    function _wrap(address user, uint128 amount) internal {
        //burn public balance
        _burn(user, uint256(amount));

        //mint encrypted balance
        _mintEnc(user, FHE.asEuint128(amount));
    }

    // --------- Encrypted Unwrapping Functions ---------------
    function requestUnwrap(address user, InEuint128 memory amount) external returns(euint128) {
        return _requestUnwrap(user, FHE.asEuint128(amount));
    }

    function requestUnwrap(address user, euint128 amount) external returns(euint128) {
        return _requestUnwrap(user, amount);
    }

    function _requestUnwrap(address user, euint128 amount) internal returns(euint128 burnAmount) {
        burnAmount = _calculateBurnAmount(user, amount);
        //request decrpytion of burn amount
        FHE.decrypt(burnAmount);
    }

    function _getUnwrapResult(address user, euint128 burnAmount) internal {
        uint128 amount = FHE.getDecryptResult(burnAmount);

        //burn encrypted balance
        _burnEnc(user, burnAmount);

        //mint public balance
        _mint(user, amount);
    }

    function _getUnwrapResultSafe(address user, euint128 burnAmount) internal returns(bool) {
        (uint128 amount, bool decrypted) = FHE.getDecryptResultSafe(burnAmount);

        if(!decrypted) return false;

        //burn encrypted balance
        _burnEnc(user, burnAmount);

        //mint public balance
        _mint(user, amount);

        return true;
    }
}
