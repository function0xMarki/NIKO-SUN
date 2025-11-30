// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SolarToken.sol";

/**
 * @title TransferDiagnosticTest
 * @notice Tests de diagnóstico para verificar que las transferencias ERC1155 funcionan correctamente
 */
contract TransferDiagnosticTest is Test {
    SolarTokenV3Optimized public token;
    address public alice = address(0xA11cE);
    address public bob = address(0xB0b);
    address public charlie = address(0xC4a411e);

    event TransferExecuted(address indexed from, address indexed to, uint256 indexed projectId, uint256 amount, uint64 timestamp);

    function setUp() public {
        token = new SolarTokenV3Optimized();
    }

    /// @notice Test básico de transferencia directa (owner transfiere sus propios tokens)
    function testBasicTransfer() public {
        // 1. Crear proyecto
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        // 2. Comprar tokens como Alice
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // 3. Verificar balance inicial
        uint256 aliceBalanceBefore = token.balanceOf(alice, projectId);
        uint256 bobBalanceBefore = token.balanceOf(bob, projectId);

        assertEq(aliceBalanceBefore, 10, "Alice should have 10 tokens");
        assertEq(bobBalanceBefore, 0, "Bob should have 0 tokens");

        // 4. Alice transfiere sus propios tokens a Bob (NO requiere aprobación)
        token.safeTransferFrom(alice, bob, projectId, 5, "");

        // 5. Verificar balances finales
        uint256 aliceBalanceAfter = token.balanceOf(alice, projectId);
        uint256 bobBalanceAfter = token.balanceOf(bob, projectId);

        assertEq(aliceBalanceAfter, 5, "Alice should have 5 tokens after transfer");
        assertEq(bobBalanceAfter, 5, "Bob should have 5 tokens after receiving");

        vm.stopPrank();
    }

    /// @notice Test de transferencia con función transferTokens mejorada
    function testTransferTokensFunction() public {
        // 1. Crear proyecto y comprar tokens
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // 2. Usar la función transferTokens mejorada
        vm.startPrank(alice);

        // Verificar que emite el evento
        vm.expectEmit(true, true, true, true);
        emit TransferExecuted(alice, bob, projectId, 3, uint64(block.timestamp));

        token.transferTokens(bob, projectId, 3);
        vm.stopPrank();

        // 3. Verificar balances
        assertEq(token.balanceOf(alice, projectId), 7, "Alice should have 7 tokens");
        assertEq(token.balanceOf(bob, projectId), 3, "Bob should have 3 tokens");
    }

    /// @notice Test de transferencia con aprobación de operador
    function testTransferWithApproval() public {
        // 1. Setup
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // 2. Alice aprueba a Charlie como operador
        vm.prank(alice);
        token.setApprovalForAll(charlie, true);

        // 3. Charlie transfiere tokens de Alice a Bob
        vm.prank(charlie);
        token.safeTransferFrom(alice, bob, projectId, 4, "");

        // 4. Verificar balances
        assertEq(token.balanceOf(alice, projectId), 6, "Alice should have 6 tokens");
        assertEq(token.balanceOf(bob, projectId), 4, "Bob should have 4 tokens");
    }

    /// @notice Test de transferencia batch
    function testBatchTransfer() public {
        // 1. Crear dos proyectos
        uint256 projectId1 = token.createProject("Project1", 1000, 0.001 ether, 1);
        uint256 projectId2 = token.createProject("Project2", 1000, 0.001 ether, 1);

        // 2. Alice compra tokens de ambos proyectos
        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        token.mint{value: 0.01 ether}(projectId1, 10);
        token.mint{value: 0.01 ether}(projectId2, 10);

        // 3. Preparar arrays para batch transfer
        uint256[] memory ids = new uint256[](2);
        ids[0] = projectId1;
        ids[1] = projectId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3;
        amounts[1] = 5;

        // 4. Transferencia batch
        token.safeBatchTransferFrom(alice, bob, ids, amounts, "");
        vm.stopPrank();

        // 5. Verificar balances
        assertEq(token.balanceOf(alice, projectId1), 7, "Alice should have 7 tokens of project 1");
        assertEq(token.balanceOf(alice, projectId2), 5, "Alice should have 5 tokens of project 2");
        assertEq(token.balanceOf(bob, projectId1), 3, "Bob should have 3 tokens of project 1");
        assertEq(token.balanceOf(bob, projectId2), 5, "Bob should have 5 tokens of project 2");
    }

    /// @notice Test que los rewards se actualizan correctamente en transferencias
    function testRewardsUpdateOnTransfer() public {
        // 1. Crear proyecto
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        // 2. Alice compra 100 tokens
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.1 ether}(projectId, 100);

        // 3. Depositar revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        token.depositRevenue{value: 0.1 ether}(projectId, 100);

        // 4. Verificar claimable antes de transferir
        uint256 aliceClaimableBefore = token.getClaimableAmount(projectId, alice);
        assertGt(aliceClaimableBefore, 0, "Alice should have claimable rewards");

        // 5. Alice transfiere la mitad de sus tokens a Bob
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, projectId, 50, "");

        // 6. Los rewards pendientes de Alice deben haberse actualizado
        uint256 aliceClaimableAfter = token.getClaimableAmount(projectId, alice);
        uint256 bobClaimable = token.getClaimableAmount(projectId, bob);

        // Alice debe mantener sus rewards acumulados antes de la transferencia
        assertEq(aliceClaimableAfter, aliceClaimableBefore, "Alice rewards should be preserved");

        // Bob no debe tener rewards del período anterior
        assertEq(bobClaimable, 0, "Bob should have 0 rewards from before he owned tokens");

        // 7. Depositar más revenue
        vm.prank(creator);
        token.depositRevenue{value: 0.1 ether}(projectId, 100);

        // 8. Ahora ambos deben tener nuevos rewards proporcionales
        uint256 aliceNewRewards = token.getClaimableAmount(projectId, alice);
        uint256 bobNewRewards = token.getClaimableAmount(projectId, bob);

        // Ambos deben tener rewards del segundo depósito (50/100 cada uno)
        assertGt(aliceNewRewards, aliceClaimableAfter, "Alice should have new rewards");
        assertGt(bobNewRewards, 0, "Bob should have new rewards");
    }

    /// @notice Test de transferencia sin suficiente balance (debe fallar)
    function testTransferInsufficientBalance() public {
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.005 ether}(projectId, 5);

        // Intentar transferir más de lo que tiene
        vm.prank(alice);
        vm.expectRevert(); // ERC1155: insufficient balance for transfer
        token.safeTransferFrom(alice, bob, projectId, 10, "");
    }

    /// @notice Test de transferencia a dirección cero (debe fallar)
    function testTransferToZeroAddress() public {
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.005 ether}(projectId, 5);

        // Intentar transferir a address(0)
        vm.prank(alice);
        vm.expectRevert(); // ERC1155: transfer to the zero address
        token.safeTransferFrom(alice, address(0), projectId, 5, "");
    }

    /// @notice Test de transferencia sin aprobación (debe fallar)
    function testTransferWithoutApproval() public {
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // Charlie intenta transferir tokens de Alice sin aprobación
        vm.prank(charlie);
        vm.expectRevert(); // ERC1155: caller is not token owner or approved
        token.safeTransferFrom(alice, bob, projectId, 5, "");
    }

    /// @notice Test de transferencia cuando el contrato está pausado
    function testTransferWhenPaused() public {
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // Pausar el contrato
        token.pause();

        // Intentar transferir (debe fallar)
        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        token.transferTokens(bob, projectId, 5);

        // Despausar y verificar que funciona
        token.unpause();

        vm.prank(alice);
        token.transferTokens(bob, projectId, 5);

        assertEq(token.balanceOf(bob, projectId), 5, "Transfer should work after unpause");
    }

    /// @notice Test de múltiples transferencias consecutivas
    function testMultipleConsecutiveTransfers() public {
        uint256 projectId = token.createProject("TestProject", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // Transferencia 1: Alice -> Bob (3 tokens)
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, projectId, 3, "");

        // Transferencia 2: Alice -> Charlie (2 tokens)
        vm.prank(alice);
        token.safeTransferFrom(alice, charlie, projectId, 2, "");

        // Transferencia 3: Bob -> Charlie (1 token)
        vm.prank(bob);
        token.safeTransferFrom(bob, charlie, projectId, 1, "");

        // Verificar balances finales
        assertEq(token.balanceOf(alice, projectId), 5, "Alice should have 5 tokens");
        assertEq(token.balanceOf(bob, projectId), 2, "Bob should have 2 tokens");
        assertEq(token.balanceOf(charlie, projectId), 3, "Charlie should have 3 tokens");
    }
}
