// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title An allowance that pays an agent's account at most a fixed amount per period.
/// @notice Unaudited draft. A sponsor deposits tokens for one account, with a limit per period
/// fixed when it opens. Only that account can draw, only to itself, and never more than the
/// limit in a period. Nobody can raise the limit; the sponsor can close the allowance and take
/// back what is left at any time. The account therefore holds only what it has drawn: that is
/// all a misled agent, or one whose machine restarted with a new key, can lose.
/// @dev Periods are fixed windows counted from the opening, so up to twice the limit can be drawn
/// across the boundary of two windows. The amount credited is what the contract received, so a
/// token that charges a fee on transfer cannot make it promise more than it holds.
contract AgentAllowance is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Allowance {
        address sponsor;
        address account;
        IERC20 token;
        uint64 period;
        uint64 start;
        uint128 perPeriod;
        uint128 drawn; // in the current window
        uint64 window; // index of the current window
        uint256 balance;
    }

    mapping(uint256 => Allowance) private _allowances;
    uint256 public count;

    event Opened(
        uint256 indexed id,
        address indexed sponsor,
        address indexed account,
        IERC20 token,
        uint128 perPeriod,
        uint64 period
    );
    event Deposited(uint256 indexed id, uint256 amount);
    event Drawn(uint256 indexed id, uint256 amount);
    event Closed(uint256 indexed id, uint256 refund);

    error BadTerms();
    error NotSponsor();
    error NotAccount();
    error OverLimit(uint256 available);

    function open(address account, IERC20 token, uint128 perPeriod, uint64 period, uint256 amount)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (account == address(0) || address(token) == address(0) || perPeriod == 0 || period == 0) {
            revert BadTerms();
        }
        id = ++count;
        Allowance storage a = _allowances[id];
        a.sponsor = msg.sender;
        a.account = account;
        a.token = token;
        a.perPeriod = perPeriod;
        a.period = period;
        a.start = uint64(block.timestamp);
        emit Opened(id, msg.sender, account, token, perPeriod, period);
        _deposit(a, id, amount);
    }

    /// Adds funds. The terms stay those of the opening.
    function deposit(uint256 id, uint256 amount) external nonReentrant {
        Allowance storage a = _allowances[id];
        if (msg.sender != a.sponsor) revert NotSponsor();
        _deposit(a, id, amount);
    }

    /// The account draws `amount` to itself, within the limit of the current period.
    function draw(uint256 id, uint256 amount) external nonReentrant {
        Allowance storage a = _allowances[id];
        if (msg.sender != a.account) revert NotAccount();
        uint256 left = available(id);
        if (amount > left) revert OverLimit(left);
        uint64 w = _window(a);
        if (w != a.window) (a.window, a.drawn) = (w, 0);
        a.drawn += uint128(amount);
        a.balance -= amount;
        emit Drawn(id, amount);
        a.token.safeTransfer(a.account, amount);
    }

    /// The sponsor closes the allowance and takes back what is left.
    function close(uint256 id) external nonReentrant {
        Allowance storage a = _allowances[id];
        if (msg.sender != a.sponsor) revert NotSponsor();
        (IERC20 token, uint256 refund) = (a.token, a.balance);
        delete _allowances[id];
        emit Closed(id, refund);
        token.safeTransfer(msg.sender, refund);
    }

    /// What the account can draw now.
    function available(uint256 id) public view returns (uint256) {
        Allowance storage a = _allowances[id];
        if (a.account == address(0)) return 0;
        uint256 left = a.perPeriod - (_window(a) == a.window ? a.drawn : 0);
        return left < a.balance ? left : a.balance;
    }

    function allowance(uint256 id) external view returns (Allowance memory) {
        return _allowances[id];
    }

    function _window(Allowance storage a) private view returns (uint64) {
        return uint64((block.timestamp - a.start) / a.period);
    }

    function _deposit(Allowance storage a, uint256 id, uint256 amount) private {
        uint256 before = a.token.balanceOf(address(this));
        a.token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = a.token.balanceOf(address(this)) - before;
        a.balance += received;
        emit Deposited(id, received);
    }
}
