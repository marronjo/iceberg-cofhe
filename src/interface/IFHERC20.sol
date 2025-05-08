pragma solidity >=0.8.19 <0.9.0;

// SPDX-License-Identifier: MIT
// Fhenix Protocol (last updated v0.1.0) (token/FHERC20/IFHERC20.sol)
// Inspired by OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts) (token/ERC20/IERC20.sol)

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InEuint128, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

interface IFHERC20 is IERC20 {
    // -------- Public Mint / Burn Functions --------
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;

    // -------- Encrypted Mint Functions --------
    function mintEncrypted(address user, InEuint128 memory amount) external;
    function mintEncrypted(address user, euint128 amount) external;

    // -------- Encrypted Burn Functions --------
    function burnEncrypted(address user, InEuint128 memory amount) external;
    function burnEncrypted(address user, euint128 amount) external;

    // -------- Encrypted Transfer Functions --------
    function transferFromEncrypted(address from, address to, InEuint128 memory amount) external returns (euint128);
    function transferFromEncrypted(address from, address to, euint128 amount) external returns (euint128);

    // -------- Decrypt Balance Functions --------
    function decryptBalance(address user) external;
    function getDecryptBalanceResult(address user) external view returns (uint128);
    function getDecryptBalanceResultSafe(address user) external view returns (uint128, bool);

    // -------- Encrypted Wrapping Functions --------
    function wrap(address user, uint128 amount) external;

    // -------- Encrypted Unwrapping Functions --------
    function requestUnwrap(address user, InEuint128 memory amount) external returns (euint128);
    function requestUnwrap(address user, euint128 amount) external returns (euint128);
    function getUnwrapResult(address user, euint128 burnAmount) external returns (uint128);
    function getUnwrapResultSafe(address user, euint128 burnAmount) external returns (uint128, bool);

    // -------- View for encrypted balances --------
    function encBalances(address user) external view returns (euint128);
}
