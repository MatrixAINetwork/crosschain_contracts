pragma solidity ^0.4.11;

contract WTokenManagerInterface {
  function lockQuota(address,address,uint) public returns(bool);
  function mintToken(address,address,uint) public returns(bool);
  function unlockQuota(address,uint) public returns(bool);

  function lockToken(address,address,uint) public returns(bool);
  function burnToken(address,uint) public returns(bool);
  function unlockToken(address,address,uint) public returns(bool);
}
