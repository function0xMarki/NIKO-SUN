// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SolarToken.sol";

/**
 * @title AuditTests
 * @notice Tests exhaustivos de auditoría para identificar vulnerabilidades y problemas de eficiencia
 * @dev Cubre: overflow, reentrancy, access control, edge cases, precision loss, DoS, etc.
 */
contract AuditTests is Test {
    SolarTokenV3Optimized public token;

    address public owner;
    address public alice = address(0xA11cE);
    address public bob = address(0xB0b);
    address public charlie = address(0xC4a71E);
    address public attacker = address(0xbad);

    uint256 constant PRECISION = 1e18;

    function setUp() public {
        owner = address(this);
        token = new SolarTokenV3Optimized();

        // Fund test accounts
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(charlie, 1000 ether);
        vm.deal(attacker, 1000 ether);
    }

    // ========================================
    // VULNERABILIDAD CORREGIDA: claimMultiple AHORA TRANSFIERE FONDOS
    // ========================================

    /// @notice Verificar que claimMultiple ahora transfiere correctamente
    function testClaimMultipleTransfersCorrectly() public {
        // Crear proyecto y hacer mint
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        // Depositar revenue
        token.depositRevenue{value: 1 ether}(projectId, 100);

        // Verificar que alice tiene rewards
        uint256 claimable = token.getClaimableAmount(projectId, alice);
        assertGt(claimable, 0, "Alice should have claimable rewards");

        uint256 aliceBalanceBefore = alice.balance;

        // Llamar claimMultiple
        uint256[] memory projectIds = new uint256[](1);
        projectIds[0] = projectId;

        vm.prank(alice);
        token.claimMultiple(projectIds);

        uint256 aliceBalanceAfter = alice.balance;

        // VERIFICAR: claimMultiple AHORA transfiere los fondos correctamente
        assertEq(
            aliceBalanceAfter,
            aliceBalanceBefore + claimable,
            "claimMultiple should transfer funds!"
        );

        // Verificar que los rewards se consumieron
        uint256 claimableAfter = token.getClaimableAmount(projectId, alice);
        assertEq(claimableAfter, 0, "Rewards should be consumed after claim");
    }

    // ========================================
    // PRECISION Y OVERFLOW
    // ========================================

    /// @notice Test de precisión con cantidades muy pequeñas de tokens
    function testPrecisionLossSmallAmounts() public {
        // Proyecto con precio bajo y pocos tokens
        uint256 projectId = token.createProject("Test", 1000000, 1 wei, 1);

        // Alice compra 1 token
        vm.prank(alice);
        token.mint{value: 1 wei}(projectId, 1);

        // Depositar revenue pequeño
        token.depositRevenue{value: 1000 wei}(projectId, 1);

        // Con 1M tokens y 1 token comprado, el cálculo es:
        // rewardIncrease = (1000 * 1e18) / 1 = 1000e18
        // earned = (1 * 1000e18) / 1e18 = 1000

        uint256 claimable = token.getClaimableAmount(projectId, alice);
        assertEq(claimable, 1000, "Should receive proportional share");
    }

    /// @notice Test de pérdida de precisión con fracciones
    function testPrecisionLossFractionalRewards() public {
        uint256 projectId = token.createProject("Test", 3, 0.01 ether, 1);

        // Alice compra 1 token, Bob compra 2
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 1);

        vm.prank(bob);
        token.mint{value: 0.02 ether}(projectId, 2);

        // Depositar 1 wei (cantidad que no se puede dividir equitativamente)
        token.depositRevenue{value: 1 wei}(projectId, 0);

        // rewardPerToken = (1 * 1e18) / 3 = 333333333333333333 (truncated)
        // alice reward = (1 * 333333333333333333) / 1e18 = 0 (truncated!)
        // bob reward = (2 * 333333333333333333) / 1e18 = 0 (truncated!)

        uint256 aliceClaimable = token.getClaimableAmount(projectId, alice);
        uint256 bobClaimable = token.getClaimableAmount(projectId, bob);

        // NOTA: Con 1 wei dividido entre 3 tokens, todos pierden por truncamiento
        // Esto es un comportamiento esperado pero puede causar "dust" atrapado
        console.log("Alice claimable:", aliceClaimable);
        console.log("Bob claimable:", bobClaimable);
    }

    /// @notice Test de overflow potencial en totalPrice
    function testOverflowTotalPrice() public {
        // Precio maximo posible con uint128 SE PERMITE crear
        // pero la multiplicacion en mint es segura (uint256)
        uint128 maxPrice = type(uint128).max;

        // Crear proyecto con precio maximo - ESTO FUNCIONA
        uint256 projectId = token.createProject("Test", 100, maxPrice, 1);

        // Pero intentar comprar causaria overflow si no fuera por el precio excesivo
        // El usuario simplemente no podra pagar
        vm.prank(alice);
        vm.expectRevert(SolarTokenV3Optimized.InsufficientPayment.selector);
        token.mint{value: 1 ether}(projectId, 1);
    }

    /// @notice Test de acumulación de totalRevenue
    function testTotalRevenueAccumulation() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        // Depositar múltiples veces
        for (uint256 i = 0; i < 10; i++) {
            token.depositRevenue{value: 1 ether}(projectId, 100);
        }

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );

        // totalRevenue es uint128, verificar que acumula correctamente
        assertEq(
            project.totalRevenue,
            10 ether,
            "Total revenue should accumulate"
        );
    }

    // ========================================
    // EDGE CASES EN TRANSFERENCIAS
    // ========================================

    /// @notice Test de rewards después de múltiples transferencias
    function testRewardsAfterMultipleTransfers() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        // Primera ronda de revenue
        token.depositRevenue{value: 1 ether}(projectId, 0);

        // Alice transfiere a Bob
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, projectId, 50, "");

        // Segunda ronda de revenue
        token.depositRevenue{value: 1 ether}(projectId, 0);

        // Bob transfiere a Charlie
        vm.prank(bob);
        token.safeTransferFrom(bob, charlie, projectId, 25, "");

        // Tercera ronda
        token.depositRevenue{value: 1 ether}(projectId, 0);

        // Verificar que todos tienen rewards correctos
        uint256 aliceClaimable = token.getClaimableAmount(projectId, alice);
        uint256 bobClaimable = token.getClaimableAmount(projectId, bob);
        uint256 charlieClaimable = token.getClaimableAmount(projectId, charlie);

        console.log("Alice claimable:", aliceClaimable);
        console.log("Bob claimable:", bobClaimable);
        console.log("Charlie claimable:", charlieClaimable);

        // Total de rewards debería ser ~3 ether (puede haber dust por redondeo)
        uint256 totalClaimable = aliceClaimable +
            bobClaimable +
            charlieClaimable;
        assertApproxEqRel(
            totalClaimable,
            3 ether,
            0.01e18,
            "Total rewards should be close to 3 ether"
        );
    }

    /// @notice Test de transferencia a sí mismo
    function testTransferToSelf() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        token.depositRevenue{value: 1 ether}(projectId, 0);

        uint256 claimableBefore = token.getClaimableAmount(projectId, alice);

        // Transferir a sí mismo
        vm.prank(alice);
        token.safeTransferFrom(alice, alice, projectId, 50, "");

        uint256 claimableAfter = token.getClaimableAmount(projectId, alice);

        // Los rewards no deberían perderse
        assertEq(
            claimableAfter,
            claimableBefore,
            "Rewards should not be lost on self-transfer"
        );
    }

    // ========================================
    // ACCESS CONTROL
    // ========================================

    /// @notice Test de creación de proyecto con address(0)
    function testCreateProjectForZeroAddress() public {
        vm.expectRevert(SolarTokenV3Optimized.InvalidCreator.selector);
        token.createProjectFor(address(0), "Test", 100, 0.01 ether, 1);
    }

    /// @notice Test de transferencia de ownership a address(0)
    function testTransferOwnershipToZero() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.expectRevert(SolarTokenV3Optimized.InvalidCreator.selector);
        token.transferProjectOwnership(projectId, address(0));
    }

    /// @notice Test de operaciones en proyecto inexistente
    function testOperationsOnNonexistentProject() public {
        uint256 fakeProjectId = 999;

        // setProjectStatus requiere ser creator, pero el proyecto no existe
        // projects[999].creator = address(0), entonces msg.sender != address(0) falla
        vm.expectRevert(SolarTokenV3Optimized.OnlyProjectCreator.selector);
        token.setProjectStatus(fakeProjectId, true);
    }

    /// @notice Test de mint en proyecto sin activar
    function testMintOnInactiveProject() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);
        token.setProjectStatus(projectId, false);

        vm.prank(alice);
        vm.expectRevert(SolarTokenV3Optimized.ProjectNotActive.selector);
        token.mint{value: 0.01 ether}(projectId, 1);
    }

    // ========================================
    // REENTRANCY TESTS
    // ========================================

    /// @notice Test de reentrancy en withdrawSales
    function testReentrancyWithdrawSales() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        // Alice compra tokens normalmente
        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        // Crear contrato atacante que recibe ERC1155
        ReentrancyAttackerWithdraw attackerContract = new ReentrancyAttackerWithdraw(
                token
            );

        // Transferir ownership al atacante (este contrato es el owner)
        token.transferProjectOwnership(projectId, address(attackerContract));

        // El atacante intenta reentrancy en withdrawSales
        // withdrawSales NO tiene nonReentrant, pero el patrón checks-effects-interactions
        // y la actualización de projectSalesBalance ANTES de la transferencia lo protege
        attackerContract.attack(projectId);

        // Verificar que el ataque NO tuvo exito (solo 1 retiro)
        console.log("Attack attempts:", attackerContract.attackCount());

        // El balance deberia ser 0 despues del retiro legitimo
        assertEq(
            token.getSalesBalance(projectId),
            0,
            "Balance should be 0 after withdrawal"
        );
    }

    // ========================================
    // DUST Y FONDOS ATRAPADOS
    // ========================================

    /// @notice Test de fondos que podrían quedar atrapados
    function testTrappedFunds() public {
        uint256 projectId = token.createProject("Test", 3, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 0.03 ether}(projectId, 3);

        // Depositar cantidad que no se divide exactamente
        token.depositRevenue{value: 10 wei}(projectId, 0);

        // rewardPerToken = (10 * 1e18) / 3 = 3333333333333333333
        // Cada holder puede reclamar: (1 * 3333333333333333333) / 1e18 = 3 wei
        // Total reclamable: 3 * 3 = 9 wei
        // 1 wei queda atrapado!

        uint256 aliceClaimable = token.getClaimableAmount(projectId, alice);
        console.log("Alice claimable (should be ~3):", aliceClaimable);

        // No hay forma de recuperar el dust atrapado
        // Esto es un comportamiento conocido pero podría documentarse
    }

    /// @notice Test de receive() que acepta ETH directo
    function testReceiveEther() public {
        // El contrato tiene receive() external payable {}
        // Cualquiera puede enviar ETH directamente, pero no hay forma de recuperarlo

        uint256 balanceBefore = address(token).balance;

        (bool success, ) = address(token).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");

        uint256 balanceAfter = address(token).balance;
        assertEq(
            balanceAfter,
            balanceBefore + 1 ether,
            "Balance should increase"
        );

        // Este ETH queda atrapado! No hay función para retirarlo
        // Solo getTotalBalance() para verlo
        console.log("Trapped ETH:", token.getTotalBalance());
    }

    // ========================================
    // GAS OPTIMIZATION TESTS
    // ========================================

    /// @notice Test de gas en _removeProjectFromUser con muchos proyectos
    function testGasRemoveProjectFromUserManyProjects() public {
        // Crear muchos proyectos para alice
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(alice);
            token.createProject("Project", 100, 0.01 ether, 1);
        }

        // Transferir el primer proyecto (worst case - buscar desde el inicio)
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transferProjectOwnership(1, bob);
        uint256 gasUsed = gasBefore - gasleft();

        console.log(
            "Gas used to transfer ownership (100 projects, first one):",
            gasUsed
        );

        // Ahora transferir el último (best case - lo encuentra inmediatamente con swap)
        gasBefore = gasleft();
        vm.prank(alice);
        token.transferProjectOwnership(100, charlie);
        gasUsed = gasBefore - gasleft();

        console.log(
            "Gas used to transfer ownership (99 projects, last one):",
            gasUsed
        );
    }

    /// @notice Test de doble actualización de rewards en transferTokens
    function testDoubleRewardUpdateInTransferTokens() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        token.depositRevenue{value: 1 ether}(projectId, 0);

        // transferTokens llama _updateRewards dos veces Y _update también lo hace
        // Esto es redundante pero no debería causar problemas de lógica

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        token.transferTokens(bob, projectId, 50);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for transferTokens:", gasUsed);

        // Comparar con safeTransferFrom directo
        token.depositRevenue{value: 1 ether}(projectId, 0);

        gasBefore = gasleft();
        vm.prank(alice);
        token.safeTransferFrom(alice, charlie, projectId, 25, "");
        uint256 gasUsedDirect = gasBefore - gasleft();

        console.log("Gas used for direct safeTransferFrom:", gasUsedDirect);
    }

    // ========================================
    // INVARIANT TESTS
    // ========================================

    /// @notice Invariant: minted nunca debe exceder totalSupply
    function testInvariantMintedNeverExceedsTotalSupply() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 0.5 ether}(projectId, 50);

        vm.prank(bob);
        token.mint{value: 0.5 ether}(projectId, 50);

        // Intentar comprar más
        vm.prank(charlie);
        vm.expectRevert(SolarTokenV3Optimized.InsufficientSupply.selector);
        token.mint{value: 0.01 ether}(projectId, 1);

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertLe(
            project.minted,
            project.totalSupply,
            "Invariant violated: minted > totalSupply"
        );
    }

    /// @notice Invariant: projectSalesBalance nunca debe ser negativo (siempre >= 0)
    function testInvariantSalesBalanceNonNegative() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        // Retirar todo - debe enviarse a una address que pueda recibir ETH
        token.withdrawSales(projectId, alice, 1 ether);

        // Intentar retirar mas
        vm.expectRevert(SolarTokenV3Optimized.InsufficientBalance.selector);
        token.withdrawSales(projectId, alice, 1 wei);
    }

    /// @notice Invariant: balance del contrato >= suma de todos los salesBalance + pendingRewards
    function testInvariantContractBalanceIntegrity() public {
        uint256 p1 = token.createProject("Test1", 100, 0.01 ether, 1);
        uint256 p2 = token.createProject("Test2", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(p1, 100);

        vm.prank(bob);
        token.mint{value: 1 ether}(p2, 100);

        // Depositar revenues
        token.depositRevenue{value: 0.5 ether}(p1, 0);
        token.depositRevenue{value: 0.5 ether}(p2, 0);

        uint256 totalSales = token.getSalesBalance(p1) +
            token.getSalesBalance(p2);
        uint256 contractBalance = token.getTotalBalance();

        // Contract balance = sales + revenues (3 ether total)
        assertEq(contractBalance, 3 ether, "Contract balance integrity");
        assertEq(totalSales, 2 ether, "Sales balance");
    }

    // ========================================
    // EDGE CASE: PROYECTO SIN TOKENS MINTADOS
    // ========================================

    /// @notice Test de operaciones en proyecto sin tokens
    function testProjectWithNoTokens() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        // Intentar depositar revenue sin tokens mintados
        vm.expectRevert(SolarTokenV3Optimized.NoTokensMinted.selector);
        token.depositRevenue{value: 1 ether}(projectId, 0);

        // updateEnergy debería funcionar
        token.updateEnergy(projectId, 100);

        // setEnergy debería funcionar
        token.setEnergy(projectId, 50, "Correction");
    }

    // ========================================
    // PAUSABLE TESTS
    // ========================================

    /// @notice Test de funciones durante pausa
    function testFunctionsDuringPause() public {
        uint256 projectId = token.createProject("Test", 100, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 1 ether}(projectId, 100);

        token.depositRevenue{value: 1 ether}(projectId, 0);

        // Pausar
        token.pause();

        // mint debería fallar
        vm.prank(bob);
        vm.expectRevert();
        token.mint{value: 0.01 ether}(projectId, 1);

        // transferTokens debería fallar
        vm.prank(alice);
        vm.expectRevert();
        token.transferTokens(bob, projectId, 10);

        // claimRevenue debería funcionar (no tiene whenNotPaused)
        vm.prank(alice);
        token.claimRevenue(projectId);

        // depositRevenue debería funcionar (no tiene whenNotPaused)
        token.depositRevenue{value: 0.1 ether}(projectId, 0);
    }
}

/**
 * @notice Contrato atacante para test de reentrancy en withdrawSales
 */
contract ReentrancyAttackerWithdraw {
    SolarTokenV3Optimized public token;
    uint256 public attackCount;
    uint256 public targetProjectId;
    bool public attacking;

    constructor(SolarTokenV3Optimized _token) {
        token = _token;
    }

    function buyTokens(uint256 projectId, uint96 amount) external payable {
        token.mint{value: msg.value}(projectId, amount);
    }

    function attack(uint256 projectId) external {
        targetProjectId = projectId;
        attacking = true;
        attackCount = 0;

        uint256 balance = token.getSalesBalance(projectId);
        if (balance > 0) {
            token.withdrawSales(projectId, address(this), balance);
        }
    }

    receive() external payable {
        if (attacking && attackCount < 5) {
            attackCount++;
            uint256 balance = token.getSalesBalance(targetProjectId);
            if (balance > 0) {
                try
                    token.withdrawSales(targetProjectId, address(this), balance)
                {
                    // Reentrancy succeeded
                } catch {
                    // Failed
                }
            }
        }
    }
}

// ========================================
// TESTS PARA rescueDust (O(1) - SIN ITERACIÓN)
// ========================================

contract RescueDustTests is Test {
    SolarTokenV3Optimized public token;

    address public owner;
    address public alice = address(0xA11cE);
    address public bob = address(0xB0b);
    address payable public treasury;

    function setUp() public {
        owner = address(this);
        token = new SolarTokenV3Optimized();
        treasury = payable(makeAddr("treasury")); // Crear EOA válido

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(owner, 1000 ether);
    }

    // Permitir recibir ETH en el contrato de test
    receive() external payable {}

    /// @notice Test que rescueDust funciona correctamente
    function testRescueDustRecoversDust() public {
        uint256 projectId = token.createProject("Test", 3, 0.01 ether, 1);

        vm.prank(alice);
        token.mint{value: 0.03 ether}(projectId, 3);

        // Verificar acumulador O(1)
        assertEq(
            token.getTotalSalesBalance(),
            0.03 ether,
            "Accumulator should track"
        );

        token.withdrawSales(projectId, owner, 0.03 ether);
        assertEq(token.getTotalSalesBalance(), 0, "Accumulator should be 0");

        (bool success, ) = address(token).call{value: 0.5 ether}("");
        assertTrue(success, "Should accept ETH");

        uint256 treasuryBefore = treasury.balance;
        token.rescueDust(treasury);

        assertEq(address(token).balance, 0, "Contract should be empty");
        assertEq(
            treasury.balance,
            treasuryBefore + 0.5 ether,
            "Treasury receives dust"
        );
    }

    /// @notice Test que rescueDust NO puede retirar salesBalance
    function testRescueDustProtectsSalesBalance() public {
        uint256 projectId = token.createProject("Test", 100, 0.1 ether, 1);

        vm.prank(alice);
        token.mint{value: 10 ether}(projectId, 100);

        assertEq(
            token.getTotalSalesBalance(),
            10 ether,
            "Accumulator tracks sales"
        );

        (bool success, ) = address(token).call{value: 0.1 ether}("");
        assertTrue(success, "Should accept ETH");

        uint256 treasuryBefore = treasury.balance;
        token.rescueDust(treasury);

        assertEq(
            treasury.balance - treasuryBefore,
            0.1 ether,
            "Only dust rescued"
        );
        assertEq(address(token).balance, 10 ether, "Sales protected");
    }

    /// @notice Test que rescueDust falla si no hay dust
    function testRescueDustFailsWhenNoDust() public {
        uint256 projectId = token.createProject("Test", 100, 0.1 ether, 1);

        vm.prank(alice);
        token.mint{value: 10 ether}(projectId, 100);

        vm.expectRevert(SolarTokenV3Optimized.NothingToClaim.selector);
        token.rescueDust(treasury);
    }

    /// @notice Test que solo el owner puede rescatar dust
    function testOnlyOwnerCanRescueDust() public {
        (bool success, ) = address(token).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");

        vm.prank(alice);
        vm.expectRevert();
        token.rescueDust(treasury);
    }

    /// @notice Test que rescueDust no permite recipient address(0)
    function testRescueDustRejectsZeroAddress() public {
        (bool success, ) = address(token).call{value: 1 ether}("");
        assertTrue(success, "Should accept ETH");

        vm.expectRevert(SolarTokenV3Optimized.InvalidCreator.selector);
        token.rescueDust(address(0));
    }

    /// @notice Test que _totalSalesBalance es consistente
    function testTotalSalesBalanceConsistency() public {
        uint256 p1 = token.createProject("P1", 100, 0.1 ether, 1);
        uint256 p2 = token.createProject("P2", 50, 0.2 ether, 1);

        vm.startPrank(alice);
        token.mint{value: 10 ether}(p1, 100);
        token.mint{value: 10 ether}(p2, 50);
        vm.stopPrank();

        // Acumulador = suma individual
        uint256 individual = token.getSalesBalance(p1) +
            token.getSalesBalance(p2);
        assertEq(
            token.getTotalSalesBalance(),
            individual,
            "Accumulator == sum"
        );
        assertEq(token.getTotalSalesBalance(), 20 ether, "Total 20 ETH");

        // Retiro parcial
        token.withdrawSales(p1, treasury, 5 ether);
        assertEq(token.getTotalSalesBalance(), 15 ether, "Decreases correctly");
    }

    /// @notice Test de gas O(1) - constante sin importar proyectos
    function testRescueDustGasO1() public {
        // Crear 50 proyectos
        for (uint256 i = 0; i < 50; i++) {
            token.createProject("P", 10, 0.001 ether, 1);
        }

        (bool success, ) = address(token).call{value: 1 ether}("");
        assertTrue(success);

        uint256 gasBefore = gasleft();
        token.rescueDust(treasury);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas constante ~50k (no itera sobre 50 proyectos)
        // Si fuera O(n) con 50 proyectos, usaría >100k
        assertLt(gasUsed, 60000, "Gas is O(1)");
        console.log("rescueDust gas (50 projects):", gasUsed);
    }
}
