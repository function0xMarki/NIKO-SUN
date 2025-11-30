// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SolarToken.sol";

/**
 * @title EfficiencyTests
 * @notice Tests de eficiencia y optimización de gas para el contrato SolarToken
 */
contract EfficiencyTests is Test {
    SolarTokenV3Optimized public token;
    address public alice = address(0xA11cE);
    address public bob = address(0xB0b);
    address public charlie = address(0xC4a411e);

    function setUp() public {
        token = new SolarTokenV3Optimized();
    }

    // ========================================
    // TESTS DE MEDICIÓN DE GAS
    // ========================================

    /// @notice Medir gas de creación de proyecto
    function testGasCreateProject() public {
        uint256 gasBefore = gasleft();
        token.createProject("SolarProject", 1000, 0.001 ether, 1);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para crear proyecto:", gasUsed);
        // Verificar que está dentro de límites razonables (< 200k gas)
        assertLt(
            gasUsed,
            200000,
            "Project creation should use less than 200k gas"
        );
    }

    /// @notice Medir gas de mint de tokens
    function testGasMintTokens() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);

        uint256 gasBefore = gasleft();
        token.mint{value: 0.01 ether}(projectId, 10);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para mint de 10 tokens:", gasUsed);
        // Verificar límite razonable (< 150k gas)
        assertLt(gasUsed, 150000, "Minting should use less than 150k gas");
    }

    /// @notice Medir gas de transferencia simple
    function testGasTransfer() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        token.mint{value: 0.01 ether}(projectId, 10);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.safeTransferFrom(alice, bob, projectId, 5, "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para transferencia simple:", gasUsed);
        assertLt(gasUsed, 100000, "Transfer should use less than 100k gas");
    }

    /// @notice Medir gas de transferencia batch
    function testGasBatchTransfer() public {
        uint256 projectId1 = token.createProject(
            "Project1",
            1000,
            0.001 ether,
            1
        );
        uint256 projectId2 = token.createProject(
            "Project2",
            1000,
            0.001 ether,
            1
        );

        vm.deal(alice, 10 ether);
        vm.startPrank(alice);
        token.mint{value: 0.01 ether}(projectId1, 10);
        token.mint{value: 0.01 ether}(projectId2, 10);

        uint256[] memory ids = new uint256[](2);
        ids[0] = projectId1;
        ids[1] = projectId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5;
        amounts[1] = 5;

        uint256 gasBefore = gasleft();
        token.safeBatchTransferFrom(alice, bob, ids, amounts, "");
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("Gas usado para batch transfer (2 proyectos):", gasUsed);
        assertLt(
            gasUsed,
            150000,
            "Batch transfer should use less than 150k gas"
        );
    }

    /// @notice Medir gas de depósito de revenue
    function testGasDepositRevenue() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.1 ether}(projectId, 100);

        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 10 ether);
        vm.prank(creator);

        uint256 gasBefore = gasleft();
        token.depositRevenue{value: 1 ether}(projectId, 100);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para depositar revenue:", gasUsed);
        assertLt(
            gasUsed,
            100000,
            "Revenue deposit should use less than 100k gas"
        );
    }

    /// @notice Medir gas de claim de revenue
    function testGasClaimRevenue() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.1 ether}(projectId, 100);

        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 10 ether);
        vm.prank(creator);
        token.depositRevenue{value: 1 ether}(projectId, 100);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.claimRevenue(projectId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para claim de revenue:", gasUsed);
        assertLt(gasUsed, 100000, "Claim should use less than 100k gas");
    }

    /// @notice Medir gas de claim multiple
    function testGasClaimMultiple() public {
        // Crear 3 proyectos y comprar tokens de cada uno
        uint256[] memory projectIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            projectIds[i] = token.createProject("Test", 1000, 0.001 ether, 1);

            vm.deal(alice, 10 ether);
            vm.prank(alice);
            token.mint{value: 0.1 ether}(projectIds[i], 100);

            address creator = token.getProjectCreator(projectIds[i]);
            vm.deal(creator, 10 ether);
            vm.prank(creator);
            token.depositRevenue{value: 0.5 ether}(projectIds[i], 100);
        }

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        token.claimMultiple(projectIds);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas usado para claim multiple (3 proyectos):", gasUsed);
        assertLt(
            gasUsed,
            230000,
            "Multiple claim should use less than 230k gas"
        );
    }

    // ========================================
    // TESTS DE ESCALABILIDAD
    // ========================================

    /// @notice Test de creación de múltiples proyectos
    function testScalabilityMultipleProjects() public {
        uint256 numProjects = 10;

        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < numProjects; i++) {
            token.createProject(
                string(abi.encodePacked("Project", vm.toString(i))),
                1000,
                0.001 ether,
                1
            );
        }
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas total para crear 10 proyectos:", gasUsed);
        console.log("Gas promedio por proyecto:", gasUsed / numProjects);

        // Verificar que el proyecto #10 se creó correctamente
        assertEq(
            token.nextProjectId(),
            numProjects + 1,
            "Should have created 10 projects"
        );
    }

    /// @notice Test de múltiples compradores en un proyecto
    function testScalabilityMultipleBuyers() public {
        uint256 projectId = token.createProject("Test", 10000, 0.001 ether, 1);

        address[] memory buyers = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            buyers[i] = address(uint160(0x1000 + i));
            vm.deal(buyers[i], 10 ether);
        }

        uint256 totalGas = 0;
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(buyers[i]);
            uint256 gasBefore = gasleft();
            token.mint{value: 0.1 ether}(projectId, 100);
            uint256 gasUsed = gasBefore - gasleft();
            totalGas += gasUsed;
        }

        console.log("Gas total para 10 compradores:", totalGas);
        console.log("Gas promedio por compra:", totalGas / 10);

        // Verificar que todos compraron
        assertEq(
            token.balanceOf(buyers[9], projectId),
            100,
            "Last buyer should have tokens"
        );
    }

    /// @notice Test de distribución de rewards entre muchos usuarios
    function testScalabilityRewardsDistribution() public {
        uint256 projectId = token.createProject("Test", 10000, 0.001 ether, 1);

        // 10 inversores compran diferentes cantidades
        address[] memory investors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            investors[i] = address(uint160(0x2000 + i));
            vm.deal(investors[i], 10 ether);

            vm.prank(investors[i]);
            token.mint{value: 0.01 ether * (i + 1)}(
                projectId,
                uint96(10 * (i + 1))
            );
        }

        // Depositar revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 100 ether);
        vm.prank(creator);
        token.depositRevenue{value: 10 ether}(projectId, 1000);

        // Verificar que todos pueden calcular sus rewards
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 claimable = token.getClaimableAmount(
                projectId,
                investors[i]
            );
            totalRewards += claimable;
            console.log("Investor", i, "claimable:", claimable);
        }

        // La suma de rewards debe ser aproximadamente 10 ether (puede haber pequeños errores de redondeo)
        assertApproxEqAbs(
            totalRewards,
            10 ether,
            1000,
            "Total rewards should equal deposited amount"
        );
    }

    // ========================================
    // TESTS DE OPTIMIZACIÓN
    // ========================================

    /// @notice Comparar gas: transferTokens vs safeTransferFrom
    function testCompareTransferMethods() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.02 ether}(projectId, 20);

        // Test safeTransferFrom
        vm.prank(alice);
        uint256 gas1Before = gasleft();
        token.safeTransferFrom(alice, bob, projectId, 5, "");
        uint256 gas1Used = gas1Before - gasleft();

        // Test transferTokens
        vm.prank(alice);
        uint256 gas2Before = gasleft();
        token.transferTokens(charlie, projectId, 5);
        uint256 gas2Used = gas2Before - gasleft();

        console.log("Gas safeTransferFrom:", gas1Used);
        console.log("Gas transferTokens:", gas2Used);
        console.log(
            "Diferencia:",
            gas2Used > gas1Used ? gas2Used - gas1Used : gas1Used - gas2Used
        );
    }

    /// @notice Verificar eficiencia de claimMultiple vs claims individuales
    function testClaimMultipleVsIndividual() public {
        uint256[] memory projectIds = new uint256[](3);

        // Setup: crear 3 proyectos y comprar tokens
        for (uint256 i = 0; i < 3; i++) {
            projectIds[i] = token.createProject("Test", 1000, 0.001 ether, 1);

            vm.deal(alice, 10 ether);
            vm.prank(alice);
            token.mint{value: 0.1 ether}(projectIds[i], 100);

            address projectCreator = token.getProjectCreator(projectIds[i]);
            vm.deal(projectCreator, 10 ether);
            vm.prank(projectCreator);
            token.depositRevenue{value: 0.3 ether}(projectIds[i], 100);
        }

        // Test claims individuales
        vm.deal(bob, 10 ether);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(bob);
            token.mint{value: 0.1 ether}(projectIds[i], 100);
        }

        address creator = token.getProjectCreator(projectIds[0]);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(creator);
            token.depositRevenue{value: 0.3 ether}(projectIds[i], 100);
        }

        uint256 gasIndividual = 0;
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(bob);
            uint256 gasBefore = gasleft();
            token.claimRevenue(projectIds[i]);
            gasIndividual += gasBefore - gasleft();
        }

        // Test claim multiple (con charlie)
        vm.deal(charlie, 10 ether);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(charlie);
            token.mint{value: 0.1 ether}(projectIds[i], 100);
        }

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(creator);
            token.depositRevenue{value: 0.3 ether}(projectIds[i], 100);
        }

        vm.prank(charlie);
        uint256 gasMultipleBefore = gasleft();
        token.claimMultiple(projectIds);
        uint256 gasMultiple = gasMultipleBefore - gasleft();

        console.log("Gas claims individuales (3):", gasIndividual);
        console.log("Gas claim multiple (3):", gasMultiple);
        console.log(
            "Ahorro:",
            gasIndividual > gasMultiple ? gasIndividual - gasMultiple : 0
        );

        // claimMultiple debería ser más eficiente
        assertLt(
            gasMultiple,
            gasIndividual,
            "claimMultiple should be more gas efficient"
        );
    }

    // ========================================
    // TESTS DE LÍMITES
    // ========================================

    /// @notice Test con supply muy grande
    function testLargeSupply() public {
        uint96 largeSupply = type(uint96).max; // Máximo valor para uint96

        uint256 projectId = token.createProject(
            "MegaProject",
            largeSupply,
            0.000001 ether, // Precio muy bajo para poder mintear mucho
            1
        );

        // Verificar que se creó correctamente
        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(
            project.totalSupply,
            largeSupply,
            "Should handle max uint96 supply"
        );
    }

    /// @notice Test con precio muy alto
    function testHighPrice() public {
        uint128 highPrice = 10 ether; // Precio alto - ahora soporta hasta 340 quintillones de ETH

        uint256 projectId = token.createProject(
            "ExpensiveProject",
            100,
            highPrice,
            1
        );

        // Comprar 1 token al precio alto
        vm.deal(alice, 200 ether);
        vm.prank(alice);
        token.mint{value: highPrice}(projectId, 1);

        assertEq(
            token.balanceOf(alice, projectId),
            1,
            "Should handle high price purchases"
        );
    }

    /// @notice Test con precio mayor a 18 ETH (anteriormente imposible con uint64)
    /// @dev Este test verifica la corrección del issue ER06
    function testPriceAbove18ETH() public {
        // 25 ETH por token - antes imposible con uint64 (máximo ~18.44 ETH)
        uint128 priceAboveOldLimit = 25 ether;

        uint256 projectId = token.createProject(
            "PremiumProject",
            100,
            priceAboveOldLimit,
            1
        );

        // Verificar que el proyecto se creó con el precio correcto
        (SolarTokenV3Optimized.Project memory project, , , ) = token.getProject(
            projectId
        );
        assertEq(
            project.priceWei,
            priceAboveOldLimit,
            "Price should be 25 ETH"
        );

        // Comprar tokens al precio premium
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        token.mint{value: 50 ether}(projectId, 2); // 2 tokens a 25 ETH cada uno

        assertEq(
            token.balanceOf(alice, projectId),
            2,
            "Should purchase 2 tokens at 25 ETH each"
        );
        assertEq(
            token.getSalesBalance(projectId),
            50 ether,
            "Sales balance should be 50 ETH"
        );
    }

    /// @notice Test con precio extremadamente alto (100 ETH)
    function testVeryHighPrice() public {
        uint128 veryHighPrice = 100 ether;

        uint256 projectId = token.createProject(
            "UltraPremium",
            10,
            veryHighPrice,
            1
        );

        vm.deal(alice, 500 ether);
        vm.prank(alice);
        token.mint{value: 300 ether}(projectId, 3);

        assertEq(
            token.balanceOf(alice, projectId),
            3,
            "Should handle 100 ETH per token"
        );
    }

    /// @notice Test con muchas transferencias consecutivas
    function testManyConsecutiveTransfers() public {
        uint256 projectId = token.createProject("Test", 10000, 0.001 ether, 1);

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        token.mint{value: 10 ether}(projectId, 10000);

        // Crear 10 addresses
        address[] memory recipients = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            recipients[i] = address(uint160(0x3000 + i));
        }

        // Alice transfiere 100 tokens a cada uno
        vm.startPrank(alice);
        uint256 totalGas = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 gasBefore = gasleft();
            token.safeTransferFrom(alice, recipients[i], projectId, 100, "");
            totalGas += gasBefore - gasleft();
        }
        vm.stopPrank();

        console.log("Gas total para 10 transferencias consecutivas:", totalGas);
        console.log("Gas promedio por transferencia:", totalGas / 10);

        // Verificar que todas las transferencias fueron exitosas
        for (uint256 i = 0; i < 10; i++) {
            assertEq(
                token.balanceOf(recipients[i], projectId),
                100,
                "Each recipient should have 100 tokens"
            );
        }
    }

    /// @notice Test de portfolio con muchos proyectos
    function testLargePortfolio() public {
        uint256 numProjects = 20;
        uint256[] memory projectIds = new uint256[](numProjects);

        // Crear 20 proyectos y comprar tokens de cada uno
        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < numProjects; i++) {
            projectIds[i] = token.createProject(
                string(abi.encodePacked("Project", vm.toString(i))),
                1000,
                0.001 ether,
                1
            );

            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Obtener portfolio
        uint256 gasBefore = gasleft();
        SolarTokenV3Optimized.InvestorPosition[] memory portfolio = token
            .getInvestorPortfolio(alice, projectIds);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas para obtener portfolio de 20 proyectos:", gasUsed);
        assertEq(portfolio.length, numProjects, "Should return all projects");

        for (uint256 i = 0; i < numProjects; i++) {
            assertEq(
                portfolio[i].tokenBalance,
                10,
                "Each position should have 10 tokens"
            );
        }
    }

    // ========================================
    // TESTS DE PRECISIÓN
    // ========================================

    /// @notice Test de precisión en rewards con números pequeños
    function testRewardsPrecisionSmallAmounts() public {
        uint256 projectId = token.createProject("Test", 1000, 0.001 ether, 1);

        // 3 inversores compran cantidades diferentes
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        token.mint{value: 0.001 ether}(projectId, 1); // 1 token

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        token.mint{value: 0.002 ether}(projectId, 2); // 2 tokens

        vm.deal(charlie, 10 ether);
        vm.prank(charlie);
        token.mint{value: 0.003 ether}(projectId, 3); // 3 tokens

        // Depositar pequeña cantidad de revenue
        address creator = token.getProjectCreator(projectId);
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        token.depositRevenue{value: 0.006 ether}(projectId, 10); // 6 tokens total

        // Verificar distribución proporcional
        uint256 aliceRewards = token.getClaimableAmount(projectId, alice); // 1/6 = 0.001 ether
        uint256 bobRewards = token.getClaimableAmount(projectId, bob); // 2/6 = 0.002 ether
        uint256 charlieRewards = token.getClaimableAmount(projectId, charlie); // 3/6 = 0.003 ether

        assertEq(aliceRewards, 0.001 ether, "Alice should get 1/6 of rewards");
        assertEq(bobRewards, 0.002 ether, "Bob should get 2/6 of rewards");
        assertEq(
            charlieRewards,
            0.003 ether,
            "Charlie should get 3/6 of rewards"
        );
        assertEq(
            aliceRewards + bobRewards + charlieRewards,
            0.006 ether,
            "Total should equal deposited"
        );
    }
}
