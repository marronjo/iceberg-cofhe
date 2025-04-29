// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DoubleEndedQueue} from "openzeppelin-contracts/contracts/utils/structs/DoubleEndedQueue.sol";

contract Queue {

    DoubleEndedQueue.Bytes32Deque private queue;

    function push(bytes32 handle) external {
        DoubleEndedQueue.pushFront(queue, handle);
    }

    function pop() external returns(bytes32) {
        return DoubleEndedQueue.popFront(queue);
    }
 
    function peek() external view returns(bytes32) {
        return DoubleEndedQueue.front(queue);
    }

    function length() external view returns(uint256) {
        return DoubleEndedQueue.length(queue);
    }

    function isEmpty() external view returns(bool) {
        return DoubleEndedQueue.empty(queue);
    }
}