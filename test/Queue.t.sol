// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

//Foundry Imports
import "forge-std/Test.sol";

import {Queue} from "../src/Queue.sol";
import {FHE, euint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {CoFheTest} from "@fhenixprotocol/cofhe-foundry-mocks/CoFheTest.sol";

contract QueueTest is Test {

    Queue private queue;
    CoFheTest private CFT;

    function setUp() public {
        queue = new Queue();
        CFT = new CoFheTest(true);  //needs to be instantiated to allow for fhe operations
    }

    modifier queueEmptyStartEnd {
        assertTrue(queue.isEmpty());
        assertEq(queue.length(), 0);
        _;
        assertTrue(queue.isEmpty());
        assertEq(queue.length(), 0);
    }

    function testPush() public queueEmptyStartEnd {
        euint128 value = FHE.asEuint128(10);
        queue.push(value);

        assertFalse(queue.isEmpty());
        assertEq(queue.length(), 1);

        assertEq(euint128.unwrap(queue.peek()), euint128.unwrap(value));
        CFT.assertHashValue(queue.peek(), 10);

        euint128 popped = queue.pop();
        assertEq(euint128.unwrap(popped), euint128.unwrap(value));
        CFT.assertHashValue(popped, 10);
    }

    function testPushTwo() public queueEmptyStartEnd {
        euint128 value1 = FHE.asEuint128(25);
        queue.push(value1);                     //[25]

        assertFalse(queue.isEmpty());
        assertEq(queue.length(), 1);

        euint128 value2 = FHE.asEuint128(47);
        queue.push(value2);                     //[25, 47] FIFO queue, 25 should be front

        assertFalse(queue.isEmpty());
        assertEq(queue.length(), 2);

        assertEq(euint128.unwrap(queue.peek()), euint128.unwrap(value1));
        CFT.assertHashValue(queue.peek(), 25);

        euint128 popped1 = queue.pop();
        assertEq(euint128.unwrap(popped1), euint128.unwrap(value1));
        CFT.assertHashValue(popped1, 25);

        euint128 popped2 = queue.pop();
        assertEq(euint128.unwrap(popped2), euint128.unwrap(value2));
        CFT.assertHashValue(popped2, 47);
    }

    function testPushFuzz(uint128 value) public queueEmptyStartEnd {
        euint128 evalue = FHE.asEuint128(value);
        queue.push(evalue);

        assertFalse(queue.isEmpty());
        assertEq(queue.length(), 1);

        assertEq(euint128.unwrap(queue.peek()), euint128.unwrap(evalue));
        CFT.assertHashValue(queue.peek(), value);

        euint128 popped = queue.pop();
        assertEq(euint128.unwrap(popped), euint128.unwrap(evalue));
        CFT.assertHashValue(popped, value);
    }

    function testPushNFuzz(uint128[] calldata values) public queueEmptyStartEnd {
        vm.assume(values.length > 1 && values.length <= 10);
        
        //push values to queue
        uint256 length = values.length;
        for(uint256 i = 0; i < length; i++){
            euint128 value = FHE.asEuint128(values[i]);
            queue.push(value);

            assertFalse(queue.isEmpty());
            assertEq(queue.length(), i+1);

            CFT.assertHashValue(queue.peek(), values[0]);   //first value should always be top of queue
        }

        //unwind queue, pop all values
        for(uint256 i = 0; i < length; i++){
            euint128 popped = queue.pop();
            CFT.assertHashValue(popped, values[i]);

            assertEq(queue.length(), length - 1 - i);       //ensure queue length decreasing each iteration
        }
    }
}