pragma solidity ^0.4.11;

contract StoremanGroupAdminInterface {

    function DEFAULT_PRECISE() public view returns(uint);

    function mapCoinInfo(uint) public view returns(uint, uint, uint, bytes, address, address, uint, bool, uint, uint, uint, uint);
    function mapCoinSmgInfo(uint, address) public view returns(uint, bytes, uint, uint, uint, address, uint);
}
