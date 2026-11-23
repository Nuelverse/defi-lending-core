// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RUSDC is ERC20, Ownable {
    address poolAddress;

    error ZeroAddress();
    error UnauthorizedCaller(address);
    error PoolAlreadySet(address);

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);

    constructor() ERC20("Receipt Token", "rUSDC") Ownable(msg.sender) {}

    function setPool(address _poolAddress) external onlyOwner {
        if (poolAddress != address(0)) {
            revert PoolAlreadySet(poolAddress);
        }
        if (_poolAddress == address(0)) {
            revert ZeroAddress();
        }
        poolAddress = _poolAddress;
    }

    modifier onlyPool() {
        if (msg.sender != poolAddress) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
        emit Burned(from, amount);
    }
}
