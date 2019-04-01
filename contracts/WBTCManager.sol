pragma solidity ^0.4.11;

import './SafeMath.sol';
import './Halt.sol';
import './WBTC.sol';

contract WBTCManager is Halt {
  using SafeMath for uint;

  /************************************************************
   **
   ** VARIABLES
   **
   ************************************************************/

  /// WBTC token address
  WBTC public WBTCToken;
  /// TotalQuota
  uint private totalQuota;
  /// StoremanGroupAdmin address
  address public storemanGroupAdmin;   
  /// HTLCWBTC contract address
  address public HTLCWBTC;

  /// A mapping from StoremanGroup address to corresponding credit-line status
  mapping(address => StoremanGroup) public mapStoremanGroup;
  /// A mapping from StoremanGroup address to unregistration application status
  mapping(address => bool) public mapUnregistration;

  /// A single storemanGroup credit-line detail
  struct StoremanGroup {
    /// This storemanGroup's total quota in BTC <<<>>> WBTC pair
    uint _quota;
    /// Amount of BTC to be received, equals to amount of WBTC to be minted
    uint _receivable;  
    /// Amount of BTC to be paied, equals to WBTC to be burnt
    uint _payable;       
    /// Amount of BTC received, equals to amount of WBTC been minted
    uint _debt;
  }

  /************************************************************
   **
   ** MODIFIERS
   **
   ************************************************************/

  /// Authorization modifiers

  /// @notice `storemanGroupAdmin` is the only address that can call a function with this modifier
  /// @dev `storemanGroupAdmin` is the only address that can call a function with this modifier
  modifier onlyStoremanGroupAdmin {
    require(msg.sender == storemanGroupAdmin);
    _;
  }

  /// @notice `HTLCWBTC` is the only address that can call a function with this modifier
  /// @dev `HTLCWBTC` is the only address that can call a function with this modifier
  modifier onlyHTLCWBTC {
    require(msg.sender == HTLCWBTC);
    _;
  }

  /// Quantity modifiers

  /// @notice Test if a value provided is meaningless
  /// @dev Test if a value provided is meaningless
  /// @param value Given value to be handled
  modifier onlyMeaningfulValue(uint value) {
    require(value > 0);
    _;
  }
  
  /************************************************************
   **
   ** EVENTS
   **
   ************************************************************/

  ///@notice Log out register storemanGroup
  ///@dev Log out register storemanGroup
  ///@param storemanGroup StoremanGroup address
  ///@param quota BTC/WBTC quota assigned to this storemanGroup
  ///@param totalQuota TotalQuota after registration
  event StoremanGroupRegistrationLogger(
    address indexed storemanGroup, 
    uint indexed quota, 
    uint indexed totalQuota
  );

  ///@notice Log out unregister storemanGroup
  ///@dev Log out unregister storemanGroup
  ///@param storemanGroup StoremanGroup address
  ///@param quota BTC/WBTC quota assigned to this storemanGroup
  ///@param totalQuota TotalQuota after unregistration
  event StoremanGroupUnregistrationLogger(
    address indexed storemanGroup, 
    uint indexed quota, 
    uint indexed totalQuota
  );
  
  /**
  * CONSTRUCTOR 
  * 
  * @notice Initialize the HTLCWBTCAddr address
  * @param HTLCAddr The HTLCWBTC address
  * @param smgAdminAddr smg address
  */
  function WBTCManager(address HTLCAddr,address smgAdminAddr)
    public
  {
      require(HTLCAddr != address(0));
      require(smgAdminAddr != address(0));
      
      HTLCWBTC = HTLCAddr;
      storemanGroupAdmin = smgAdminAddr;

      WBTCToken = new WBTC(this);
  }

  /****************************************************************************
   **
   ** MANIPULATIONS
   **
   ****************************************************************************/

  /// @notice Register a storemanGroup
  /// @dev Register a storemanGroup
  /// @param storemanGroup Address of the storemanGroup to be registered
  /// @param quota This storemanGroup's quota in WBTC/BTC pair
  /// @return Result of registering the provided address, true if successful
  function registerStoremanGroup(address storemanGroup, uint quota)
    public
    notHalted
    onlyStoremanGroupAdmin 
    onlyMeaningfulValue(quota) 
    returns (bool)
  {
    /// Make sure a valid storemanGroup address provided
    require(storemanGroup != address(0));
    require(!isStoremanGroup(storemanGroup));

    /// Create an instance of storemanGroup
    mapStoremanGroup[storemanGroup] = StoremanGroup(quota, 0, 0, 0);
    /// Update totalQuota 
    totalQuota = totalQuota.add(quota);
    /// Fire StoremanGroupRegistrationLogger event
    emit StoremanGroupRegistrationLogger(storemanGroup, quota, totalQuota);

    return true;
  }

  /// @dev Unregister a storemanGroup
  /// @param storemanGroup Address of the storemanGroup to be unregistered
  /// @return Result of unregistering provided storemanGroup, true if successful
  function unregisterStoremanGroup(address storemanGroup)
    public
    notHalted 
    onlyStoremanGroupAdmin 
    returns (bool)
  {
    /// Make sure a valid storemanGroup address provided
    require(mapUnregistration[storemanGroup]);
    /// Make sure the given storemanGroup has paid off its debt
    require(isDebtPaidOff(storemanGroup));

    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];
    /// remove this storemanGroup from the unregistration intention map
    mapUnregistration[storemanGroup] = false;
    /// adjust total quota
    totalQuota = totalQuota.sub(_s._quota);

    /// Fire the UnregisterStoremanGroup event
    emit StoremanGroupUnregistrationLogger(storemanGroup, _s._quota, totalQuota);
    
    /// Reset quota
    _s._quota = uint(0);

    return true;
  }

  /// @notice StoremanGroup unregistration application
  /// @dev StoremanGroup unregistration application
  /// @param storemanGroup StoremanGroup's address
  function applyUnregistration(address storemanGroup)
    public
    notHalted
    onlyStoremanGroupAdmin
    returns (bool) 
  {
    /// Reject unqualified storemanGroup address
    require(isActiveStoremanGroup(storemanGroup));

    mapUnregistration[storemanGroup] = true;

    return true;
  }   

  /// @notice Frozen WBTC quota
  /// @dev Frozen WBTC quota
  /// @param storemanGroup Handler address 
  /// @param recipient Recipient's address, and it could be a storemanGroup applied unregistration
  /// @param value Amout of WBTC quota to be frozen
  /// @return True if successful
  function lockQuota(address storemanGroup, address recipient, uint value)
    public
    notHalted 
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  {
    /// Make sure an active storemanGroup is provided to handle transactions
    require(isActiveStoremanGroup(storemanGroup));
    /// Make sure a valid recipient provided
    require(!isActiveStoremanGroup(recipient));

    /// Make sure enough inbound quota available
    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];
    require(_s._quota.sub(_s._receivable.add(_s._debt)) >= value);

    /// Only can be called by an unregistration applied storemanGroup reset its receivable and payable
    if (mapUnregistration[recipient]) {
      StoremanGroup storage _r = mapStoremanGroup[recipient];
      require(_r._receivable == 0 && _r._payable == 0 && _r._debt != 0);
    }
    
    /// Increase receivable
    _s._receivable = _s._receivable.add(value);

    return true;
  }

  /// @notice Defrozen WBTC quota
  /// @dev Defrozen WBTC quota
  /// @param storemanGroup Handler address
  /// @param value Amount of WBTC quota to be locked
  /// @return True if successful
  function unlockQuota(address storemanGroup, uint value) 
    public
    notHalted
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  {
    /// Make sure a valid storeman provided
    require(isStoremanGroup(storemanGroup));
    
    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];

    /// Make sure this specified storemanGroup has enough inbound receivable to be unlocked
    require(_s._receivable >= value);

    /// Credit receivable, double-check receivable is no less than value to be unlocked
    _s._receivable = _s._receivable.sub(value);

    return true;
  }

  /// @notice Mint WBTC token or payoff storemanGroup debt
  /// @dev Mint WBTC token or payoff storemanGroup debt
  /// @param storemanGroup Handler address
  /// @param recipient Address that will receive WBTC token
  /// @param value Amount of WBTC token to be minted
  /// @return Success of token mint
  function mintToken(address storemanGroup, address recipient, uint value)
    public
    notHalted
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  {
    /// Make sure a legit storemanGroup provided
    require(isStoremanGroup(storemanGroup));
    /// Make sure a legit recipient provided
    require(!isActiveStoremanGroup(recipient));

    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];

    /// Adjust quota record
    _s._receivable = _s._receivable.sub(value);
    _s._debt = _s._debt.add(value);

    /// Branch - mint token to an ordinary account
    if (!isStoremanGroup(recipient)) {
      /// Mint token to the recipient
      require(WBTCToken.mint(recipient, value));

      return true;
      
    } else if (mapUnregistration[recipient]) {
      /// Branch - storemanGroup unregistration
      StoremanGroup storage _r = mapStoremanGroup[recipient];
      /// Adjust the unregistering smg debt
      if (value >= _r._debt) {
        _r._debt = 0;
      } else {
        _r._debt = _r._debt.sub(value);
      }

      return true;
    }

    return false;
  }

  /// @notice Lock WBTC token and initiate an outbound transaction
  /// @dev Lock WBTC token and initiate an outbound transaction
  /// @param storemanGroup Outbound storemanGroup handler address
  /// @param value Amount of WBTC token to be locked
  /// @return Success of token locking
  function lockToken(address storemanGroup, address initiator, uint value)
    public
    notHalted
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  { 
    /// Make sure a valid storemanGroup and a legit initiator provided
    require(isActiveStoremanGroup(storemanGroup));
    require(!isStoremanGroup(initiator));

    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];
    /// Make sure it has enough outboundQuota 
    require(_s._debt.sub(_s._payable) >= value);
    
    /// Adjust quota record
    _s._payable = _s._payable.add(value);

    /// Handle token transfer
    require(WBTCToken.lockTo(initiator, HTLCWBTC, value));

    return true;
  }

  /// @notice Unlock WBTC token
  /// @dev Unlock WBTC token
  /// @param storemanGroup StoremanGroup handler address
  /// @param value Amount of token to be unlocked
  /// @return Success of token unlocking
  function unlockToken(address storemanGroup, address recipient, uint value) 
    public
    notHalted
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  {
    require(isStoremanGroup(storemanGroup));
    /// Make sure it has enough quota for a token unlocking
    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];
    require(_s._payable >= value);

    /// Adjust quota record
    _s._payable = _s._payable.sub(value);

    /// Handle token transfer
    require(WBTCToken.lockTo(HTLCWBTC, recipient, value));

    return true;
  }

  /// @notice Burn WBTC token
  /// @dev Burn WBTC token
  /// @param storemanGroup Crosschain transaction handler address
  /// @param value Amount of WBTC token to be burnt
  /// @return Success of burn token
  function burnToken(address storemanGroup, uint value) 
    public
    notHalted
    onlyHTLCWBTC
    onlyMeaningfulValue(value)
    returns (bool)
  { 
    require(isStoremanGroup(storemanGroup));
    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];

    /// Adjust quota record
    _s._debt = _s._debt.sub(value);
    _s._payable = _s._payable.sub(value);

    /// Process the transaction
    require(WBTCToken.burn(HTLCWBTC, value));
    return true;
  }

  /// @notice Query storemanGroup detail
  /// @dev Query storemanGroup detail
  /// @param storemanGroup StoremanGroup to be queried
  /// @return quota Total quota of this storemanGroup in BTC/WBTC
  /// @return inboundQuota Inbound crosschain transaction quota of this storemanGroup in BTC/WBTC
  /// @return outboundQuota Outbound crosschain transaction quota of this storemanGroup in BTC/WBTC
  /// @return receivable Amount of WBTC to be minted through this storemanGroup
  /// @return payable Amount of WBTC to be burnt through this storemanGroup
  /// @return debt Amount of WBTC been minted through this storemanGroup
  function getStoremanGroup(address storemanGroup)
    public 
    view
    returns (uint, uint, uint, uint, uint, uint)
  {
    if (!isStoremanGroup(storemanGroup)) {
        return (0, 0, 0, 0, 0, 0);
    }
    
    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];

    uint inboundQuota = _s._quota.sub(_s._receivable.add(_s._debt));
    uint outboundQuota = _s._debt.sub(_s._payable);
    
    return (_s._quota, inboundQuota, outboundQuota, _s._receivable, _s._payable, _s._debt);
  }

  /// @notice Check if a specified address is a valid storemanGroup
  /// @dev Check if a specified address is a valid storemanGroup
  /// @param storemanGroup The storemanGroup's address to be checked 
  /// @return Result of validity check, true is successful, false in case failed
  function isStoremanGroup(address storemanGroup)
    public
    view
    returns (bool)
  {
    return mapStoremanGroup[storemanGroup]._quota != uint(0);
  }

  /// @notice Check if a specified address is active to handle cross chain transaction
  /// @dev Check if a specified address is active to handle cross chain transaction
  /// @param storemanGroup The storemanGroup's address to be checked
  /// @return Result of validity check, true is successful, false in case failed 
  function isActiveStoremanGroup(address storemanGroup) 
    public
    view 
    returns (bool)
  {
    return isStoremanGroup(storemanGroup) && !mapUnregistration[storemanGroup];
  }

  /// @notice Query totalQuota
  /// @dev Query totalQuota
  /// @return Quota in BTC/WBTC
  function getTotalQuota()
    public
    onlyOwner
    view
    returns (uint)
  {
    return totalQuota;
  }

  /// @notice destruct SC and transfer balance to owner
  /// @dev destruct SC and transfer balance to owner
  function kill()
    public
    onlyOwner
    isHalted
  {
    selfdestruct(owner);
  }

  /// Private methods

  /// @notice Check if a specified storemanGroup has paid off its debt
  /// @dev Check if a specified storemanGroup has paid off its debt
  /// @param storemanGroup The storemanGroup's address to be checked 
  /// @return Result of debt status check
  function isDebtPaidOff(address storemanGroup)
    private
    view
    returns (bool)
  {

    StoremanGroup storage _s = mapStoremanGroup[storemanGroup];
    return _s._receivable == uint(0) && _s._payable == uint(0) && _s._debt == uint(0);
  }

  /// Fallback

  /// @notice If WAN coin is sent to this address, send it back.
  /// @dev If WAN coin is sent to this address, send it back.
  function () 
    public
    payable 
  {
    revert();
  }
}
