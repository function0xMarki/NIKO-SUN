// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SolarToken.sol";

/**
 * @title SecurityTests
 * @notice Tests de seguridad comprehensivos para el contrato SolarToken
 */
contract SecurityTests is Test {
    SolarTokenV3Optimized public token;
    address public alice = address(0xA11cE);
    address public bob = address(0xB0b);
    address public attacker = address(0xbad);

    function setUp() public {
        token = new SolarTokenV3Optimized();
    }

    // ========================================
    // TESTS DE CONTROL DE ACCESO
    // ========================================

    /// @notice Solo el owner puede pausar el contrato
    function testOnlyOwnerCanPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.pause();
    }

    /// @notice Solo el owner puede despausar el contrato
    function testOnlyOwnerCanUnpause() public {
        token.pause();

        vm.prank(attacker);
        vm.expectRevert();
        token.unpause();
    }

    /// @notice Solo el owner puede establecer el baseURI
    function testOnlyOwnerCanSetBaseURI() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.setBaseURI("https://malicious.com/");
    }

    /// @notice Solo el creador del proyecto puede transferir ownership
    function testOnlyCreatorCanTransferProjectOwnership() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OnlyProjectCreator()"));
        token.transferProjectOwnership(projectId, attacker);
    }

    /// @notice Solo el creador puede cambiar el estado del proyecto
    function testOnlyCreatorCanSetProjectStatus() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OnlyProjectCreator()"));
        token.setProjectStatus(projectId, false);
    }

    /// @notice Solo el creador puede retirar fondos de ventas
    function testOnlyCreatorCanWithdrawSales() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OnlyProjectCreator()"));
        token.withdrawSales(projectId, attacker, 0.01 ether);
    }

    /// @notice Solo el creador o admin puede depositar revenue
    function testOnlyCreatorOrAdminCanDepositRevenue() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        token.depositRevenue{value: 0.1 ether}(projectId, 100);
    }

    // ========================================
    // TESTS DE REENTRANCY
    // ========================================

    /// @notice Test de protección contra reentrancy en mint
    function testReentrancyProtectionMint() public {
        ReentrantAttacker attackerContract = new ReentrantAttacker(token);
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(address(attackerContract), 10 ether);

        // El ataque no debe revertir completamente, pero solo debe mintear una vez
        attackerContract.attackMint(projectId);

        // Verificar que solo se mintearon 10 tokens (del primer mint), no 20 (que sería con reentrancy exitoso)
        uint256 balance = token.balanceOf(address(attackerContract), projectId);
        assertEq(
            balance,
            10,
            "Should only mint once due to reentrancy protection"
        );
    }

    /// @notice Test de protección contra reentrancy en claimRevenue
    function testReentrancyProtectionClaim() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Comprar tokens con el atacante
        ReentrantAttacker attackerContract = new ReentrantAttacker(token);
        vm.deal(address(attackerContract), 10 ether);
        attackerContract.buyTokens{value: 1 ether}(projectId, 100);

        // Depositar revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        token.depositRevenue{value: 0.5 ether}(projectId, 100);

        // Intentar ataque de reentrancy en claim
        vm.expectRevert(); // Debe fallar por reentrancy guard
        attackerContract.attackClaim(projectId);
    }

    // ========================================
    // TESTS DE VALIDACIÓN DE PARÁMETROS
    // ========================================

    /// @notice No se puede crear proyecto con supply = 0
    function testCannotCreateProjectWithZeroSupply() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidSupply()"));
        token.createProject("Test", 0, 0.001 ether, 1);
    }

    /// @notice No se puede crear proyecto con price = 0
    function testCannotCreateProjectWithZeroPrice() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice()"));
        token.createProject("Test", 1000, 0, 1);
    }

    /// @notice No se puede crear proyecto con minPurchase = 0
    function testCannotCreateProjectWithZeroMinPurchase() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidMinPurchase()"));
        token.createProject("Test", 1000, 0.001 ether, 0);
    }

    /// @notice No se puede crear proyecto con minPurchase > totalSupply
    function testCannotCreateProjectWithInvalidMinPurchase() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidMinPurchase()"));
        token.createProject("Test", 1000, 0.001 ether, 1001);
    }

    /// @notice No se puede transferir ownership a address(0)
    function testCannotTransferOwnershipToZeroAddress() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.expectRevert(abi.encodeWithSignature("InvalidCreator()"));
        token.transferProjectOwnership(projectId, address(0));
    }

    /// @notice No se puede comprar menos del mínimo
    function testCannotBuyBelowMinimum() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 10);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("BelowMinimumPurchase(uint96)", 10)
        );
        token.mint{value: 0.005 ether}(projectId, 5);
    }

    /// @notice No se puede comprar más del supply disponible
    function testCannotExceedSupply() public {
        uint256 projectId = token.createProject("Test", 100, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientSupply()"));
        token.mint{value: 1 ether}(projectId, 101);
    }

    /// @notice No se puede comprar sin pagar suficiente
    function testCannotBuyWithInsufficientPayment() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientPayment()"));
        token.mint{value: 0.005 ether}(projectId, 10); // Necesita 0.01 ether
    }

    // ========================================
    // TESTS DE INTEGRIDAD DE REWARDS
    // ========================================

    /// @notice Los rewards se distribuyen correctamente entre múltiples inversores
    function testRewardsDistributionIntegrity() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Alice compra 30 tokens
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.03 ether}(projectId, 30);

        // Bob compra 70 tokens
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        token.mint{value: 0.07 ether}(projectId, 70);

        // Depositar 1 ether de revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 10 ether);
        vm.prank(creator);
        token.depositRevenue{value: 1 ether}(projectId, 100);

        // Verificar rewards proporcionales
        uint256 aliceRewards = token.getClaimableAmount(projectId, alice);
        uint256 bobRewards = token.getClaimableAmount(projectId, bob);

        // Alice debe recibir 30% (0.3 ether), Bob 70% (0.7 ether)
        assertEq(aliceRewards, 0.3 ether, "Alice should get 30% of rewards");
        assertEq(bobRewards, 0.7 ether, "Bob should get 70% of rewards");

        // Verificar que la suma es correcta
        assertEq(
            aliceRewards + bobRewards,
            1 ether,
            "Total rewards should equal deposited amount"
        );
    }

    /// @notice No se pueden reclamar rewards que no existen
    function testCannotClaimNonExistentRewards() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NothingToClaim()"));
        token.claimRevenue(projectId);
    }

    /// @notice No se puede depositar revenue sin fondos
    function testCannotDepositZeroRevenue() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        address creator = token.getProjectCreator(projectId);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("NoFundsDeposited()"));
        token.depositRevenue{value: 0}(projectId, 100);
    }

    /// @notice No se puede depositar revenue si no hay tokens minted
    function testCannotDepositRevenueWithoutTokens() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("NoTokensMinted()"));
        token.depositRevenue{value: 0.1 ether}(projectId, 100);
    }

    /// @notice Los rewards no se pierden después de una transferencia
    function testRewardsNotLostAfterTransfer() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Alice compra 100 tokens
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.1 ether}(projectId, 100);

        // Depositar revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 10 ether);
        vm.prank(creator);
        token.depositRevenue{value: 1 ether}(projectId, 100);

        // Verificar rewards de Alice antes de transferir
        uint256 aliceRewardsBefore = token.getClaimableAmount(projectId, alice);
        assertEq(
            aliceRewardsBefore,
            1 ether,
            "Alice should have 1 ether claimable"
        );

        // Alice transfiere todos sus tokens a Bob
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, projectId, 100, "");

        // Los rewards de Alice deben permanecer
        uint256 aliceRewardsAfter = token.getClaimableAmount(projectId, alice);
        assertEq(
            aliceRewardsAfter,
            1 ether,
            "Alice should still have 1 ether claimable"
        );

        // Alice debe poder reclamar
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        token.claimRevenue(projectId);
        uint256 aliceBalanceAfter = alice.balance;

        assertEq(
            aliceBalanceAfter - aliceBalanceBefore,
            1 ether,
            "Alice should receive her rewards"
        );
    }

    // ========================================
    // TESTS DE ESTADO DEL CONTRATO
    // ========================================

    /// @notice No se puede comprar cuando el proyecto está inactivo
    function testCannotBuyWhenProjectInactive() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Desactivar proyecto
        token.setProjectStatus(projectId, false);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ProjectNotActive()"));
        token.mint{value: 0.01 ether}(projectId, 10);
    }

    /// @notice No se puede depositar revenue cuando el proyecto está inactivo
    function testCannotDepositRevenueWhenInactive() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // Desactivar proyecto
        token.setProjectStatus(projectId, false);

        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("ProjectNotActive()"));
        token.depositRevenue{value: 0.1 ether}(projectId, 100);
    }

    /// @notice No se puede transferir cuando el contrato está pausado (función transferTokens)
    function testCannotTransferWhenPaused() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        // Pausar
        token.pause();

        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        token.transferTokens(bob, projectId, 5);
    }

    // ========================================
    // TESTS DE OVERFLOW/UNDERFLOW
    // ========================================

    /// @notice No se puede retirar más fondos de los disponibles
    function testCannotWithdrawMoreThanAvailable() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        address creator = token.getProjectCreator(projectId);
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance()"));
        token.withdrawSales(projectId, creator, 1 ether); // Solo hay 0.01 ether
    }

    /// @notice Verificar que no hay pérdida de fondos en refunds
    function testRefundIntegrity() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        uint256 aliceBalanceBefore = alice.balance;

        // Pagar de más
        vm.prank(alice);
        token.mint{value: 0.02 ether}(projectId, 10); // Solo necesita 0.01 ether

        uint256 aliceBalanceAfter = alice.balance;

        // Debe recibir refund de 0.01 ether
        assertEq(
            aliceBalanceBefore - aliceBalanceAfter,
            0.01 ether,
            "Alice should be refunded excess payment"
        );
    }

    // ========================================
    // TESTS DE INTEGRIDAD CONTABLE
    // ========================================

    /// @notice La suma de balances de sales debe coincidir con lo recaudado
    function testSalesBalanceIntegrity() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.03 ether}(projectId, 30);

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        token.mint{value: 0.07 ether}(projectId, 70);

        uint256 salesBalance = token.getSalesBalance(projectId);
        assertEq(
            salesBalance,
            0.1 ether,
            "Sales balance should equal total sales"
        );
    }

    /// @notice El balance total del contrato debe ser correcto
    function testContractBalanceIntegrity() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Ventas
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.1 ether}(projectId, 100);

        // Revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 10 ether);
        vm.prank(creator);
        token.depositRevenue{value: 0.5 ether}(projectId, 100);

        uint256 totalBalance = token.getTotalBalance();
        assertEq(
            totalBalance,
            0.6 ether,
            "Contract should have 0.6 ether (0.1 sales + 0.5 revenue)"
        );
    }

    // ========================================
    // TESTS DE setEnergy (ER08)
    // ========================================

    /// @notice Test que setEnergy establece correctamente el valor absoluto
    function testSetEnergyAbsoluteValue() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Primero agregar algo de energía con updateEnergy
        token.updateEnergy(projectId, 500);

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(project.totalEnergyKwh, 500, "Energy should be 500");

        // Ahora establecer un valor absoluto menor (corregir)
        token.setEnergy(projectId, 300, "Correccion: error de lectura");

        (project, , , ) = token.getProject(projectId);
        assertEq(
            project.totalEnergyKwh,
            300,
            "Energy should be corrected to 300"
        );
    }

    /// @notice Test que setEnergy puede reducir el valor
    function testSetEnergyCanReduce() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // Agregar energía inicial
        token.updateEnergy(projectId, 1000);

        // Reducir debido a panel dañado
        token.setEnergy(projectId, 800, "Panel danado: produccion reducida");

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(
            project.totalEnergyKwh,
            800,
            "Energy should be reduced to 800"
        );
    }

    /// @notice Test que setEnergy puede establecer a cero
    function testSetEnergyCanSetToZero() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        token.updateEnergy(projectId, 1000);
        token.setEnergy(projectId, 0, "Reset: mantenimiento completo");

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(project.totalEnergyKwh, 0, "Energy should be reset to 0");
    }

    /// @notice Test que solo creator o admin puede llamar setEnergy
    function testOnlyCreatorOrAdminCanSetEnergy() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.prank(attacker);
        vm.expectRevert();
        token.setEnergy(projectId, 100, "Intento malicioso");
    }

    /// @notice Test que setEnergy falla en proyecto inactivo
    function testSetEnergyFailsOnInactiveProject() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        token.setProjectStatus(projectId, false);

        vm.expectRevert(SolarTokenV3Optimized.ProjectNotActive.selector);
        token.setEnergy(projectId, 100, "Proyecto inactivo");
    }

    /// @notice Test que setEnergy emite el evento correcto
    function testSetEnergyEmitsEvent() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        token.updateEnergy(projectId, 500);

        vm.expectEmit(true, false, false, true);
        emit SolarTokenV3Optimized.EnergySet(
            projectId,
            500,
            300,
            "Correccion",
            uint64(block.timestamp)
        );

        token.setEnergy(projectId, 300, "Correccion");
    }

    /// @notice Test que el admin (owner) puede llamar setEnergy en cualquier proyecto
    function testAdminCanSetEnergyOnAnyProject() public {
        // Alice crea el proyecto
        vm.prank(alice);
        uint256 projectId = token.createProject(
            "AliceProject",
            1000,
            0.001 ether,
            1
        );

        // Alice agrega energía
        vm.prank(alice);
        token.updateEnergy(projectId, 500);

        // El owner (this contract) puede corregir
        token.setEnergy(projectId, 300, "Admin correccion");

        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(
            project.totalEnergyKwh,
            300,
            "Admin should be able to set energy"
        );
    }

    // ========================================
    // TESTS DE getUserProjects (UX Improvement)
    // ========================================

    /// @notice Test que getUserProjects devuelve proyectos del creador
    function testGetUserProjectsReturnsCreatorProjects() public {
        // Alice crea 3 proyectos
        vm.startPrank(alice);
        uint256 p1 = token.createProject("Project1", 100, 0.001 ether, 1);
        uint256 p2 = token.createProject("Project2", 200, 0.002 ether, 1);
        uint256 p3 = token.createProject("Project3", 300, 0.003 ether, 1);
        vm.stopPrank();

        uint256[] memory aliceProjects = token.getUserProjects(alice);

        assertEq(aliceProjects.length, 3, "Alice should have 3 projects");
        assertEq(aliceProjects[0], p1, "First project should be p1");
        assertEq(aliceProjects[1], p2, "Second project should be p2");
        assertEq(aliceProjects[2], p3, "Third project should be p3");
    }

    /// @notice Test que getUserProjects devuelve array vacío para usuario sin proyectos
    function testGetUserProjectsEmptyForNewUser() public {
        uint256[] memory bobProjects = token.getUserProjects(bob);
        assertEq(bobProjects.length, 0, "Bob should have no projects");
    }

    /// @notice Test que getUserProjectsCount retorna el conteo correcto
    function testGetUserProjectsCount() public {
        vm.startPrank(alice);
        token.createProject("Project1", 100, 0.001 ether, 1);
        token.createProject("Project2", 200, 0.002 ether, 1);
        vm.stopPrank();

        assertEq(
            token.getUserProjectsCount(alice),
            2,
            "Alice should have 2 projects"
        );
        assertEq(
            token.getUserProjectsCount(bob),
            0,
            "Bob should have 0 projects"
        );
    }

    /// @notice Test que transferProjectOwnership actualiza los arrays correctamente
    function testTransferOwnershipUpdatesUserProjects() public {
        // Alice crea un proyecto
        vm.prank(alice);
        uint256 projectId = token.createProject(
            "AliceProject",
            100,
            0.001 ether,
            1
        );

        assertEq(
            token.getUserProjectsCount(alice),
            1,
            "Alice should have 1 project"
        );
        assertEq(
            token.getUserProjectsCount(bob),
            0,
            "Bob should have 0 projects"
        );

        // Alice transfiere a Bob
        vm.prank(alice);
        token.transferProjectOwnership(projectId, bob);

        assertEq(
            token.getUserProjectsCount(alice),
            0,
            "Alice should have 0 projects after transfer"
        );
        assertEq(
            token.getUserProjectsCount(bob),
            1,
            "Bob should have 1 project after transfer"
        );

        uint256[] memory bobProjects = token.getUserProjects(bob);
        assertEq(
            bobProjects[0],
            projectId,
            "Bob's project should be the transferred one"
        );
    }

    /// @notice Test de paginación de proyectos por usuario
    function testGetUserProjectsPaginated() public {
        // Alice crea 10 proyectos
        vm.startPrank(alice);
        for (uint256 i = 0; i < 10; i++) {
            token.createProject("Project", 100, 0.001 ether, 1);
        }
        vm.stopPrank();

        // Primera página (5 proyectos)
        (uint256[] memory page1, uint256 total, bool hasMore) = token
            .getUserProjectsPaginated(alice, 0, 5);
        assertEq(page1.length, 5, "First page should have 5 projects");
        assertEq(total, 10, "Total should be 10");
        assertTrue(hasMore, "Should have more pages");

        // Segunda página
        (uint256[] memory page2, , bool hasMore2) = token
            .getUserProjectsPaginated(alice, 5, 5);
        assertEq(page2.length, 5, "Second page should have 5 projects");
        assertFalse(hasMore2, "Should not have more pages");

        // Offset fuera de rango
        (uint256[] memory empty, , ) = token.getUserProjectsPaginated(
            alice,
            100,
            5
        );
        assertEq(
            empty.length,
            0,
            "Should return empty array for out of range offset"
        );
    }

    /// @notice Test que múltiples usuarios tienen proyectos independientes
    function testMultipleUsersIndependentProjects() public {
        vm.prank(alice);
        token.createProject("AliceProject", 100, 0.001 ether, 1);

        vm.prank(bob);
        token.createProject("BobProject1", 200, 0.002 ether, 1);
        vm.prank(bob);
        token.createProject("BobProject2", 300, 0.003 ether, 1);

        assertEq(
            token.getUserProjectsCount(alice),
            1,
            "Alice should have 1 project"
        );
        assertEq(
            token.getUserProjectsCount(bob),
            2,
            "Bob should have 2 projects"
        );
    }
}

/**
 * @notice Contrato atacante para tests de reentrancy
 */
contract ReentrantAttacker {
    SolarTokenV3Optimized public token;
    bool public attacking = false;
    uint256 public attackProjectId;

    constructor(SolarTokenV3Optimized _token) {
        token = _token;
    }

    function attackMint(uint256 projectId) external {
        attacking = true;
        attackProjectId = projectId;
        token.mint{value: 0.01 ether}(projectId, 10);
    }

    function attackClaim(uint256 projectId) external {
        attacking = true;
        attackProjectId = projectId;
        token.claimRevenue(projectId);
    }

    function buyTokens(uint256 projectId, uint96 amount) external payable {
        token.mint{value: msg.value}(projectId, amount);
    }

    // Implementar IERC1155Receiver para poder recibir tokens
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return
            interfaceId == 0x4e2312e0 || // ERC1155Receiver
            interfaceId == 0x01ffc9a7; // ERC165
    }

    receive() external payable {
        if (attacking) {
            // Intentar reentrar
            token.mint{value: 0.01 ether}(attackProjectId, 10);
        }
    }
}
