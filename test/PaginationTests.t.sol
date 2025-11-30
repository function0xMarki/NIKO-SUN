// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/SolarToken.sol";

/**
 * @title PaginationTests
 * @notice Tests para la paginación de getInvestorPortfolio
 */
contract PaginationTests is Test {
    SolarTokenV3Optimized public token;
    address public alice = address(0xA11cE);

    function setUp() public {
        token = new SolarTokenV3Optimized();
    }

    // ========================================
    // TESTS DE LÍMITE EN FUNCIÓN ORIGINAL
    // ========================================

    /// @notice La función original debe aceptar hasta 100 proyectos
    function testGetPortfolioWithin100Limit() public {
        // Crear 50 proyectos
        uint256[] memory projectIds = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        // Alice compra tokens de todos
        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Debe funcionar sin problemas
        SolarTokenV3Optimized.InvestorPosition[] memory portfolio = token
            .getInvestorPortfolio(alice, projectIds);

        assertEq(portfolio.length, 50, "Should return all 50 positions");
        assertEq(
            portfolio[0].tokenBalance,
            10,
            "First position should have 10 tokens"
        );
        assertEq(
            portfolio[49].tokenBalance,
            10,
            "Last position should have 10 tokens"
        );
    }

    /// @notice La función original debe rechazar más de 100 proyectos
    function testGetPortfolioRejectsOver100() public {
        // Crear array con 101 IDs (aunque no existan los proyectos)
        uint256[] memory projectIds = new uint256[](101);
        for (uint256 i = 0; i < 101; i++) {
            projectIds[i] = i + 1;
        }

        // Debe revertir
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        token.getInvestorPortfolio(alice, projectIds);
    }

    /// @notice Exactamente 100 proyectos debe funcionar
    function testGetPortfolioWith100Projects() public {
        // Crear array con 100 IDs
        uint256[] memory projectIds = new uint256[](100);

        // Crear primeros 10 proyectos reales para testing
        for (uint256 i = 0; i < 10; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        // Llenar el resto con IDs (aunque no existan)
        for (uint256 i = 10; i < 100; i++) {
            projectIds[i] = i + 1;
        }

        // Debe funcionar (no revertir)
        SolarTokenV3Optimized.InvestorPosition[] memory portfolio = token
            .getInvestorPortfolio(alice, projectIds);

        assertEq(portfolio.length, 100, "Should return 100 positions");
    }

    // ========================================
    // TESTS DE PAGINACIÓN
    // ========================================

    /// @notice Test básico de paginación - primera página
    function testPaginationFirstPage() public {
        // Crear 30 proyectos
        uint256[] memory projectIds = new uint256[](30);
        for (uint256 i = 0; i < 30; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        // Alice compra de todos
        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 30; i++) {
            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Obtener primera página (10 items)
        (
            SolarTokenV3Optimized.InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        ) = token.getInvestorPortfolioPaginated(alice, projectIds, 0, 10);

        assertEq(positions.length, 10, "First page should have 10 items");
        assertEq(total, 30, "Total should be 30");
        assertTrue(hasMore, "Should have more pages");
        assertEq(
            positions[0].projectId,
            projectIds[0],
            "First item should match"
        );
        assertEq(
            positions[9].projectId,
            projectIds[9],
            "Last item should match"
        );
    }

    /// @notice Test de paginación - página del medio
    function testPaginationMiddlePage() public {
        // Crear 30 proyectos
        uint256[] memory projectIds = new uint256[](30);
        for (uint256 i = 0; i < 30; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 30; i++) {
            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Obtener segunda página (offset 10, limit 10)
        (
            SolarTokenV3Optimized.InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        ) = token.getInvestorPortfolioPaginated(alice, projectIds, 10, 10);

        assertEq(positions.length, 10, "Second page should have 10 items");
        assertEq(total, 30, "Total should be 30");
        assertTrue(hasMore, "Should have more pages");
        assertEq(
            positions[0].projectId,
            projectIds[10],
            "First item should be index 10"
        );
        assertEq(
            positions[9].projectId,
            projectIds[19],
            "Last item should be index 19"
        );
    }

    /// @notice Test de paginación - última página (parcial)
    function testPaginationLastPagePartial() public {
        // Crear 25 proyectos
        uint256[] memory projectIds = new uint256[](25);
        for (uint256 i = 0; i < 25; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 25; i++) {
            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Obtener tercera página (offset 20, limit 10, pero solo hay 5)
        (
            SolarTokenV3Optimized.InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        ) = token.getInvestorPortfolioPaginated(alice, projectIds, 20, 10);

        assertEq(positions.length, 5, "Last page should have only 5 items");
        assertEq(total, 25, "Total should be 25");
        assertFalse(hasMore, "Should NOT have more pages");
        assertEq(
            positions[0].projectId,
            projectIds[20],
            "First item should be index 20"
        );
        assertEq(
            positions[4].projectId,
            projectIds[24],
            "Last item should be index 24"
        );
    }

    /// @notice Test de paginación - offset fuera de rango
    function testPaginationOffsetOutOfRange() public {
        // Crear 10 proyectos
        uint256[] memory projectIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        // Offset 20 cuando solo hay 10
        (
            SolarTokenV3Optimized.InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        ) = token.getInvestorPortfolioPaginated(alice, projectIds, 20, 10);

        assertEq(positions.length, 0, "Should return empty array");
        assertEq(total, 10, "Total should still be 10");
        assertFalse(hasMore, "Should NOT have more");
    }

    /// @notice Test de paginación - límite máximo por página
    function testPaginationMaxLimitPerPage() public {
        // Crear 150 proyectos
        uint256[] memory projectIds = new uint256[](150);
        for (uint256 i = 0; i < 10; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }
        // Llenar resto con IDs ficticios
        for (uint256 i = 10; i < 150; i++) {
            projectIds[i] = i + 1;
        }

        // Intentar obtener más de 100 por página
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        token.getInvestorPortfolioPaginated(alice, projectIds, 0, 101);
    }

    /// @notice Test de paginación - exactamente 100 por página (límite)
    function testPaginationExactly100PerPage() public {
        // Crear 200 proyectos
        uint256[] memory projectIds = new uint256[](200);
        for (uint256 i = 0; i < 10; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }
        for (uint256 i = 10; i < 200; i++) {
            projectIds[i] = i + 1;
        }

        // Obtener 100 (el máximo permitido)
        (
            SolarTokenV3Optimized.InvestorPosition[] memory positions,
            uint256 total,
            bool hasMore
        ) = token.getInvestorPortfolioPaginated(alice, projectIds, 0, 100);

        assertEq(positions.length, 100, "Should return 100 items");
        assertEq(total, 200, "Total should be 200");
        assertTrue(hasMore, "Should have more");
    }

    /// @notice Test de múltiples páginas - iterar todo el portfolio
    function testPaginationIterateAll() public {
        // Crear 35 proyectos
        uint256[] memory projectIds = new uint256[](35);
        for (uint256 i = 0; i < 35; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 35; i++) {
            uint256 amount = 10 + i;
            vm.prank(alice);
            token.mint{value: amount * 0.001 ether}(
                projectIds[i],
                uint96(amount)
            ); // Diferentes cantidades
        }

        // Iterar en páginas de 10
        uint256 pageSize = 10;
        uint256 totalFetched = 0;

        for (uint256 offset = 0; offset < 35; offset += pageSize) {
            (
                SolarTokenV3Optimized.InvestorPosition[] memory positions,
                uint256 total,
                bool hasMore
            ) = token.getInvestorPortfolioPaginated(
                    alice,
                    projectIds,
                    offset,
                    pageSize
                );

            totalFetched += positions.length;

            // Verificar que los balances son correctos
            for (uint256 i = 0; i < positions.length; i++) {
                uint256 expectedBalance = 10 + (offset + i);
                assertEq(
                    positions[i].tokenBalance,
                    expectedBalance,
                    "Balance should match expected"
                );
            }

            if (offset + pageSize >= 35) {
                assertFalse(hasMore, "Last page should not have more");
            } else {
                assertTrue(hasMore, "Should have more pages");
            }
        }

        assertEq(totalFetched, 35, "Should have fetched all 35 items");
    }

    /// @notice Test de paginación con proyectos sin balance
    function testPaginationWithZeroBalances() public {
        // Crear 20 proyectos
        uint256[] memory projectIds = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            projectIds[i] = token.createProject(
                "Project",
                1000,
                0.001 ether,
                1
            );
        }

        // Alice solo compra de 5 proyectos
        vm.deal(alice, 100 ether);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            token.mint{value: 0.01 ether}(projectIds[i], 10);
        }

        // Obtener todo el portfolio
        (SolarTokenV3Optimized.InvestorPosition[] memory positions, , ) = token
            .getInvestorPortfolioPaginated(alice, projectIds, 0, 20);

        // Verificar que los primeros 5 tienen balance, el resto no
        for (uint256 i = 0; i < 20; i++) {
            if (i < 5) {
                assertEq(
                    positions[i].tokenBalance,
                    10,
                    "First 5 should have balance"
                );
            } else {
                assertEq(
                    positions[i].tokenBalance,
                    0,
                    "Rest should have 0 balance"
                );
            }
        }
    }

    /// @notice Gas benchmark - página completa
    function testGasPaginationFullPage() public {
        uint256[] memory projectIds = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            projectIds[i] = i + 1; // IDs ficticios
        }

        uint256 gasBefore = gasleft();
        token.getInvestorPortfolioPaginated(alice, projectIds, 0, 100);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas para obtener 100 items paginados:", gasUsed);
        // Esto es view function, el gas es solo estimado
    }
}
