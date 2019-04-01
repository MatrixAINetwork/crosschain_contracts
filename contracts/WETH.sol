pragma solidity ^0.4.11;

import './StandardToken.sol';
import './Owned.sol';

contract WETH is StandardToken, Owned {
  /**************************************
   **
   ** VARIABLES
   **
   **************************************/

  string public constant name = "Wanchain Ethereum Crosschain Token";
  string public constant symbol = "WETH";
  uint8 public constant decimals = 18;

  /// WETH manager address
  address public tokenManager;

  /****************************************************************************
   **
   ** MODIFIERS
   **
   ****************************************************************************/
  modifier onlyWETHManager {
      require(tokenManager == msg.sender);
      _;
  }

  modifier onlyMeaningfulValue(uint value) {
      require(value > 0);
      _;
  }

  /****************************************************************************
   **
   ** EVENTS
   **
   ****************************************************************************/
  /// @notice Logger for token mint
  /// @dev Logger for token mint
  /// @param account Whom these token will be minted to
  /// @param value Amount of ETH/WETH to be minted
  /// @param totalSupply Total amount of WETH after token mint
  event TokenMintedLogger(
    address indexed account, 
    uint indexed value,
    uint indexed totalSupply
  );

  /// @notice Logger for token burn
  /// @dev Logger for token burn
  /// @param account Initiator address
  /// @param value Amount of WETH to be burnt
  /// @param totalSupply Total amount of WETH after token burn
  event TokenBurntLogger(
    address indexed account,
    uint indexed value, 
    uint indexed totalSupply
  );

  /// @notice Logger for token lock
  /// @dev Logger for token lock
  /// @param from Address of sender
  /// @param to Address of recipient
  /// @param value Amount of WETH to be locked
  event TokenLockedLogger(
    address indexed from,
    address indexed to,
    uint indexed value
  );

  /// @notice Token manager address update logger
  /// @dev Token manager address update logger
  /// @param manager WETHManager address
  event WETHManagerLogger(
    address indexed manager
  );
  
  /**
  * CONSTRUCTOR 
  * 
  * @notice Initialize the WETHManager address
  * @param WETHManagerAddr The WETHManager address
  */
     
  function WETH(address WETHManagerAddr)
    public
  {
      tokenManager = WETHManagerAddr;
      emit WETHManagerLogger(WETHManagerAddr);
  }

  /****************************************************************************
   **
   ** MANIPULATIONS
   **
   ****************************************************************************/

  /// @notice Create token
  /// @dev Create token
  /// @param account Address will receive token
  /// @param value Amount of token to be minted
  /// @return True if successful
  function mint(address account, uint value)
    public
    onlyWETHManager
    onlyMeaningfulValue(value)
    returns (bool)
  {
    require(account != address(0));

    balances[account] = balances[account].add(value);
    totalSupply = totalSupply.add(value);
    
    emit TokenMintedLogger(account, value, totalSupply);
    
    return true;
  }

  /// @notice Burn token
  /// @dev Burn token
  /// @param account Address of whose token will be burnt
  /// @param value Amount of token to be burnt
  /// @return True if successful
  function burn(address account, uint value)
    public
    onlyWETHManager
    onlyMeaningfulValue(value)
    returns (bool)
  {
    balances[account] = balances[account].sub(value);
    totalSupply = totalSupply.sub(value);

    emit TokenBurntLogger(account, value, totalSupply);
    
    return true;
  }

  /// @notice Lock token from `from` to `to`
  /// @dev Lock token from `from` to `to`
  /// @param from Address transfer token
  /// @param to Address receives token
  /// @param value Amount of token to be transfer
  /// @return True if successful
  function lockTo(address from, address to, uint value)
    public
    onlyWETHManager
    onlyMeaningfulValue(value)
    returns (bool)
  {
    /// Forbidden self transfer
    require(from != to);

    balances[from] = balances[from].sub(value);
    balances[to] = balances[to].add(value);
    
    emit TokenLockedLogger(from, to, value);

    return true;
  }

  /// @notice If WAN coin is sent to this address, send it back.
  /// @dev If WAN coin is sent to this address, send it back.
  function () 
    public
    payable 
  {
    revert();
  }
  
}
