-- shupick_v2 schema only; exported 2026-10-09 (Asia/Seoul).
-- Open this file in MySQL Workbench connected to a MySQL 8.0.16+ server and execute all statements.
-- Creates and selects shupick_v2. Table data and existing AUTO_INCREMENT counters are excluded.
-- Existing tables are not dropped. Use a server without existing shupick_v2 tables.

-- MySQL dump 10.13  Distrib 8.0.46, for Win64 (x86_64)
--
-- Host: 127.0.0.1    Database: shupick_v2
-- ------------------------------------------------------
-- Server version	8.0.46

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Current Database: `shupick_v2`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `shupick_v2` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `shupick_v2`;

--
-- Table structure for table `after_sales_inspections`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `after_sales_inspections` (
  `after_sales_inspection_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `return_request_id` bigint unsigned NOT NULL,
  `inspection_stage` varchar(20) NOT NULL,
  `inspected_by_employee_id` bigint unsigned NOT NULL,
  `has_wear_marks` tinyint(1) NOT NULL DEFAULT '0',
  `has_product_damage` tinyint(1) NOT NULL DEFAULT '0',
  `has_customer_fault` tinyint(1) NOT NULL DEFAULT '0',
  `components_complete` tinyint(1) NOT NULL DEFAULT '1',
  `packaging_intact` tinyint(1) NOT NULL DEFAULT '1',
  `has_product_defect` tinyint(1) NOT NULL DEFAULT '0',
  `is_wrong_item` tinyint(1) NOT NULL DEFAULT '0',
  `inspection_decision` varchar(20) NOT NULL DEFAULT 'PENDING',
  `inspection_notes` text,
  `inspected_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`after_sales_inspection_id`),
  UNIQUE KEY `uq_after_sales_inspection_stage` (`return_request_id`,`inspection_stage`),
  KEY `idx_after_sales_inspections_employee` (`inspected_by_employee_id`),
  CONSTRAINT `fk_after_sales_inspections_employee` FOREIGN KEY (`inspected_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_after_sales_inspections_return_request` FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_after_sales_inspections_decision` CHECK ((`inspection_decision` in (_utf8mb4'PENDING',_utf8mb4'ACCEPTED',_utf8mb4'REJECTED'))),
  CONSTRAINT `chk_after_sales_inspections_stage` CHECK ((`inspection_stage` in (_utf8mb4'BRANCH',_utf8mb4'HEADQUARTERS')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `approval_workflow_steps`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `approval_workflow_steps` (
  `approval_workflow_step_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `approval_workflow_id` bigint unsigned NOT NULL,
  `step_order` tinyint unsigned NOT NULL,
  `step_name` varchar(100) NOT NULL,
  `required_role_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`approval_workflow_step_id`),
  UNIQUE KEY `uq_approval_workflow_steps_order` (`approval_workflow_id`,`step_order`),
  KEY `idx_approval_workflow_steps_role` (`required_role_id`),
  CONSTRAINT `fk_approval_workflow_steps_role` FOREIGN KEY (`required_role_id`) REFERENCES `roles` (`role_id`),
  CONSTRAINT `fk_approval_workflow_steps_workflow` FOREIGN KEY (`approval_workflow_id`) REFERENCES `approval_workflows` (`approval_workflow_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_approval_workflow_steps_order` CHECK ((`step_order` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `approval_workflows`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `approval_workflows` (
  `approval_workflow_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `workflow_code` varchar(50) NOT NULL,
  `workflow_name` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`approval_workflow_id`),
  UNIQUE KEY `uq_approval_workflows_code` (`workflow_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `audit_logs`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_logs` (
  `audit_log_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `actor_type` varchar(20) NOT NULL,
  `actor_employee_id` bigint unsigned DEFAULT NULL,
  `actor_customer_id` bigint unsigned DEFAULT NULL,
  `action_code` varchar(80) NOT NULL,
  `entity_type` varchar(50) NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  `before_data` json DEFAULT NULL,
  `after_data` json DEFAULT NULL,
  `request_id` varchar(100) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`audit_log_id`),
  KEY `idx_audit_logs_entity_time` (`entity_type`,`entity_id`,`created_at`),
  KEY `idx_audit_logs_employee_time` (`actor_employee_id`,`created_at`),
  KEY `idx_audit_logs_customer_time` (`actor_customer_id`,`created_at`),
  CONSTRAINT `fk_audit_logs_customer` FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_audit_logs_employee` FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_audit_logs_actor` CHECK ((((`actor_type` = _utf8mb4'SYSTEM') and (`actor_employee_id` is null) and (`actor_customer_id` is null)) or ((`actor_type` = _utf8mb4'EMPLOYEE') and (`actor_employee_id` is not null) and (`actor_customer_id` is null)) or ((`actor_type` = _utf8mb4'CUSTOMER') and (`actor_employee_id` is null) and (`actor_customer_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `branch_business_hours`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `branch_business_hours` (
  `branch_business_hour_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `branch_id` bigint unsigned NOT NULL,
  `day_of_week` tinyint unsigned NOT NULL COMMENT '1=Monday, 7=Sunday',
  `opens_at` time DEFAULT NULL,
  `closes_at` time DEFAULT NULL,
  `is_closed` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`branch_business_hour_id`),
  UNIQUE KEY `uq_branch_business_hours_day` (`branch_id`,`day_of_week`),
  CONSTRAINT `fk_branch_business_hours_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_branch_business_hours_day` CHECK ((`day_of_week` between 1 and 7)),
  CONSTRAINT `chk_branch_business_hours_time` CHECK ((((`is_closed` = true) and (`opens_at` is null) and (`closes_at` is null)) or ((`is_closed` = false) and (`opens_at` is not null) and (`closes_at` is not null) and (`opens_at` < `closes_at`))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `branches`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `branches` (
  `branch_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `branch_code` varchar(20) NOT NULL,
  `branch_name` varchar(100) NOT NULL,
  `district_code` varchar(20) NOT NULL DEFAULT 'UNASSIGNED',
  `address` varchar(255) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `latitude` decimal(10,7) DEFAULT NULL,
  `longitude` decimal(10,7) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`branch_id`),
  UNIQUE KEY `uq_branches_code` (`branch_code`),
  KEY `idx_branches_district_code` (`district_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `brands`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `brands` (
  `brand_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `brand_code` varchar(10) NOT NULL,
  `brand_name` varchar(100) NOT NULL,
  PRIMARY KEY (`brand_id`),
  UNIQUE KEY `uq_brands_code` (`brand_code`),
  UNIQUE KEY `uq_brands_name` (`brand_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `cart_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cart_items` (
  `cart_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `product_variant_id` bigint unsigned NOT NULL,
  `quantity` int unsigned NOT NULL DEFAULT '1',
  `added_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`cart_item_id`),
  UNIQUE KEY `uq_cart_customer_variant` (`customer_id`,`product_variant_id`),
  KEY `idx_cart_variant` (`product_variant_id`),
  CONSTRAINT `fk_cart_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_cart_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_cart_quantity` CHECK ((`quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `categories`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `categories` (
  `category_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `parent_category_id` bigint unsigned DEFAULT NULL,
  `category_code` varchar(10) NOT NULL,
  `category_name` varchar(100) NOT NULL,
  PRIMARY KEY (`category_id`),
  UNIQUE KEY `uq_categories_code` (`category_code`),
  KEY `idx_categories_parent` (`parent_category_id`),
  CONSTRAINT `fk_categories_parent` FOREIGN KEY (`parent_category_id`) REFERENCES `categories` (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `coupon_definitions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `coupon_definitions` (
  `coupon_definition_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `coupon_code` varchar(40) NOT NULL,
  `coupon_name` varchar(100) NOT NULL,
  `discount_type` varchar(20) NOT NULL,
  `discount_value` int unsigned NOT NULL,
  `minimum_order_amount` int unsigned NOT NULL DEFAULT '0',
  `maximum_discount_amount` int unsigned DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`coupon_definition_id`),
  UNIQUE KEY `uq_coupon_definitions_code` (`coupon_code`),
  CONSTRAINT `chk_coupon_definitions_type` CHECK ((`discount_type` in (_utf8mb4'PERCENT',_utf8mb4'FIXED'))),
  CONSTRAINT `chk_coupon_definitions_value` CHECK ((((`discount_type` = _utf8mb4'PERCENT') and (`discount_value` between 1 and 100)) or ((`discount_type` = _utf8mb4'FIXED') and (`discount_value` > 0))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `coupon_refund_policies`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `coupon_refund_policies` (
  `coupon_refund_policy_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `policy_name` varchar(100) NOT NULL,
  `effective_from` date NOT NULL,
  `effective_to` date DEFAULT NULL,
  `restore_on_full_cancel` tinyint(1) NOT NULL DEFAULT '1',
  `restore_on_partial_return` tinyint(1) NOT NULL DEFAULT '0',
  `require_unexpired_coupon` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`coupon_refund_policy_id`),
  UNIQUE KEY `uq_coupon_refund_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_coupon_refund_policies_period` CHECK (((`effective_to` is null) or (`effective_to` >= `effective_from`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `coupon_restorations`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `coupon_restorations` (
  `coupon_restoration_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_coupon_id` bigint unsigned NOT NULL,
  `refund_id` bigint unsigned NOT NULL,
  `coupon_refund_policy_id` bigint unsigned NOT NULL,
  `previous_status` varchar(20) NOT NULL,
  `restoration_reason` varchar(255) NOT NULL,
  `restored_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`coupon_restoration_id`),
  UNIQUE KEY `uq_coupon_restorations_coupon_refund` (`customer_coupon_id`,`refund_id`),
  KEY `idx_coupon_restorations_refund` (`refund_id`),
  KEY `idx_coupon_restorations_policy` (`coupon_refund_policy_id`),
  CONSTRAINT `fk_coupon_restorations_coupon` FOREIGN KEY (`customer_coupon_id`) REFERENCES `customer_coupons` (`customer_coupon_id`),
  CONSTRAINT `fk_coupon_restorations_policy` FOREIGN KEY (`coupon_refund_policy_id`) REFERENCES `coupon_refund_policies` (`coupon_refund_policy_id`),
  CONSTRAINT `fk_coupon_restorations_refund` FOREIGN KEY (`refund_id`) REFERENCES `refunds` (`refund_id`),
  CONSTRAINT `chk_coupon_restorations_previous_status` CHECK ((`previous_status` in (_utf8mb4'USED',_utf8mb4'EXPIRED',_utf8mb4'REVOKED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_coupons`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_coupons` (
  `customer_coupon_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `coupon_definition_id` bigint unsigned NOT NULL,
  `benefit_month` date NOT NULL,
  `issue_sequence` tinyint unsigned NOT NULL,
  `coupon_status` varchar(20) NOT NULL DEFAULT 'AVAILABLE',
  `issued_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `expires_at` datetime NOT NULL,
  `used_order_id` bigint unsigned DEFAULT NULL,
  `used_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_coupon_id`),
  UNIQUE KEY `uq_customer_coupons_monthly_issue` (`customer_id`,`coupon_definition_id`,`benefit_month`,`issue_sequence`),
  KEY `idx_customer_coupons_order` (`used_order_id`),
  KEY `fk_customer_coupons_definition` (`coupon_definition_id`),
  CONSTRAINT `fk_customer_coupons_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_customer_coupons_definition` FOREIGN KEY (`coupon_definition_id`) REFERENCES `coupon_definitions` (`coupon_definition_id`),
  CONSTRAINT `fk_customer_coupons_order` FOREIGN KEY (`used_order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_customer_coupons_expiry` CHECK ((`expires_at` >= `issued_at`)),
  CONSTRAINT `chk_customer_coupons_month` CHECK ((dayofmonth(`benefit_month`) = 1)),
  CONSTRAINT `chk_customer_coupons_status` CHECK ((`coupon_status` in (_utf8mb4'AVAILABLE',_utf8mb4'USED',_utf8mb4'EXPIRED',_utf8mb4'REVOKED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_enrollments`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_enrollments` (
  `customer_id` bigint unsigned NOT NULL,
  `verified_phone` varchar(20) NOT NULL,
  `firebase_phone_uid` varchar(128) NOT NULL,
  `phone_verified_at` datetime(6) NOT NULL,
  `phone_consent_at` datetime(6) NOT NULL,
  `birth_date_consent_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`customer_id`),
  KEY `idx_enrollments_phone` (`verified_phone`),
  CONSTRAINT `fk_enrollments_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_interaction_events`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_interaction_events` (
  `interaction_event_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `event_key` varchar(100) NOT NULL,
  `customer_id` bigint unsigned NOT NULL,
  `session_key` varchar(100) NOT NULL,
  `product_id` bigint unsigned NOT NULL,
  `event_type` varchar(30) NOT NULL,
  `color_name` varchar(50) DEFAULT NULL,
  `size_mm` smallint unsigned DEFAULT NULL,
  `quantity` smallint unsigned DEFAULT NULL,
  `occurred_at` datetime(6) NOT NULL,
  `received_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`interaction_event_id`),
  UNIQUE KEY `uq_interaction_event_key` (`event_key`),
  KEY `idx_interactions_customer_session` (`customer_id`,`session_key`,`occurred_at`,`interaction_event_id`),
  KEY `idx_interactions_product_type` (`product_id`,`event_type`,`occurred_at`),
  CONSTRAINT `fk_interactions_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_interactions_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_interactions_type` CHECK ((`event_type` in (_utf8mb4'VIEW',_utf8mb4'WISH_ADD',_utf8mb4'WISH_REMOVE',_utf8mb4'CART_ADD',_utf8mb4'CART_REMOVE',_utf8mb4'CART_QUANTITY',_utf8mb4'CART_OPTION')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customers`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customers` (
  `customer_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `firebase_uid` varchar(128) NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `customer_name` varchar(100) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `birth_date` date DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` datetime DEFAULT NULL,
  PRIMARY KEY (`customer_id`),
  UNIQUE KEY `uq_customers_firebase_uid` (`firebase_uid`),
  UNIQUE KEY `uq_customers_email` (`email`),
  UNIQUE KEY `uq_customers_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `deliveries`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `deliveries` (
  `delivery_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `delivery_status` varchar(30) NOT NULL DEFAULT 'PREPARING',
  `recipient_name` varchar(100) NOT NULL,
  `recipient_phone` varchar(20) NOT NULL,
  `postal_code` varchar(10) NOT NULL,
  `address` varchar(255) NOT NULL,
  `address_detail` varchar(255) DEFAULT NULL,
  `tracking_number` varchar(100) DEFAULT NULL,
  `shipped_at` datetime DEFAULT NULL,
  `delivered_at` datetime DEFAULT NULL,
  PRIMARY KEY (`delivery_id`),
  UNIQUE KEY `uq_deliveries_order` (`order_id`),
  UNIQUE KEY `uq_deliveries_tracking` (`tracking_number`),
  CONSTRAINT `fk_deliveries_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_deliveries_status` CHECK ((`delivery_status` in (_utf8mb4'PREPARING',_utf8mb4'SHIPPED',_utf8mb4'IN_TRANSIT',_utf8mb4'DELIVERED',_utf8mb4'RETURNED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `employee_branch_assignments`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `employee_branch_assignments` (
  `assignment_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `employee_id` bigint unsigned NOT NULL,
  `branch_id` bigint unsigned NOT NULL,
  `assigned_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` datetime DEFAULT NULL,
  PRIMARY KEY (`assignment_id`),
  KEY `idx_assignments_employee` (`employee_id`),
  KEY `idx_assignments_branch` (`branch_id`),
  CONSTRAINT `fk_assignments_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_assignments_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `chk_assignments_period` CHECK (((`ended_at` is null) or (`ended_at` >= `assigned_at`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `employee_roles`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `employee_roles` (
  `employee_id` bigint unsigned NOT NULL,
  `role_id` bigint unsigned NOT NULL,
  `assigned_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `assigned_by_employee_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`employee_id`,`role_id`),
  KEY `idx_employee_roles_role` (`role_id`),
  KEY `idx_employee_roles_assigner` (`assigned_by_employee_id`),
  CONSTRAINT `fk_employee_roles_assigner` FOREIGN KEY (`assigned_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_employee_roles_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_employee_roles_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `employees`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `employees` (
  `employee_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `firebase_uid` varchar(128) NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `employee_code` varchar(45) NOT NULL,
  `employee_name` varchar(100) NOT NULL,
  `department` varchar(50) NOT NULL,
  `position` varchar(50) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`employee_id`),
  UNIQUE KEY `uq_employees_code` (`employee_code`),
  UNIQUE KEY `uq_employees_firebase_uid` (`firebase_uid`),
  UNIQUE KEY `uq_employees_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `favorites`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `favorites` (
  `customer_id` bigint unsigned NOT NULL,
  `product_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`,`product_id`),
  KEY `idx_favorites_product` (`product_id`),
  CONSTRAINT `fk_favorites_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_favorites_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `fulfillment_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `fulfillment_items` (
  `fulfillment_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `fulfillment_id` bigint unsigned NOT NULL,
  `order_id` bigint unsigned NOT NULL,
  `order_item_id` bigint unsigned NOT NULL,
  `quantity` int unsigned NOT NULL,
  PRIMARY KEY (`fulfillment_item_id`),
  UNIQUE KEY `uq_fulfillment_items_order_item` (`fulfillment_id`,`order_item_id`),
  UNIQUE KEY `uq_fulfillment_items_id_order` (`fulfillment_item_id`,`order_id`),
  KEY `idx_fulfillment_items_order_item_order` (`order_item_id`,`order_id`),
  KEY `fk_fulfillment_items_fulfillment_order` (`fulfillment_id`,`order_id`),
  CONSTRAINT `fk_fulfillment_items_fulfillment_order` FOREIGN KEY (`fulfillment_id`, `order_id`) REFERENCES `fulfillments` (`fulfillment_id`, `order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_fulfillment_items_order_item_order` FOREIGN KEY (`order_item_id`, `order_id`) REFERENCES `order_items` (`order_item_id`, `order_id`),
  CONSTRAINT `chk_fulfillment_items_quantity` CHECK ((`quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `fulfillment_status_history`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `fulfillment_status_history` (
  `fulfillment_status_history_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `fulfillment_id` bigint unsigned NOT NULL,
  `previous_status` varchar(30) DEFAULT NULL,
  `new_status` varchar(30) NOT NULL,
  `change_source` varchar(30) NOT NULL,
  `change_reason` varchar(255) DEFAULT NULL,
  `actor_type` varchar(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_employee_id` bigint unsigned DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`fulfillment_status_history_id`),
  KEY `idx_fulfillment_status_history_time` (`fulfillment_id`,`changed_at`),
  KEY `idx_fulfillment_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_fulfillment_status_history_employee` FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_fulfillment_status_history_fulfillment` FOREIGN KEY (`fulfillment_id`) REFERENCES `fulfillments` (`fulfillment_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_fulfillment_status_history_actor` CHECK ((((`actor_type` = _utf8mb4'SYSTEM') and (`actor_employee_id` is null)) or ((`actor_type` = _utf8mb4'EMPLOYEE') and (`actor_employee_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `fulfillments`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `fulfillments` (
  `fulfillment_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `fulfillment_number` varchar(32) NOT NULL,
  `order_id` bigint unsigned NOT NULL,
  `destination_branch_id` bigint unsigned NOT NULL,
  `fulfillment_status` varchar(30) NOT NULL DEFAULT 'PREPARING',
  `tracking_number` varchar(100) DEFAULT NULL,
  `shipped_at` datetime DEFAULT NULL,
  `arrived_at` datetime DEFAULT NULL,
  `inspected_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`fulfillment_id`),
  UNIQUE KEY `uq_fulfillments_number` (`fulfillment_number`),
  UNIQUE KEY `uq_fulfillments_id_order` (`fulfillment_id`,`order_id`),
  UNIQUE KEY `uq_fulfillments_tracking` (`tracking_number`),
  KEY `idx_fulfillments_order` (`order_id`),
  KEY `idx_fulfillments_branch_status` (`destination_branch_id`,`fulfillment_status`),
  CONSTRAINT `fk_fulfillments_branch` FOREIGN KEY (`destination_branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_fulfillments_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_fulfillments_status` CHECK ((`fulfillment_status` in (_utf8mb4'PREPARING',_utf8mb4'IN_TRANSIT',_utf8mb4'ARRIVED',_utf8mb4'INSPECTING',_utf8mb4'READY_FOR_PICKUP',_utf8mb4'RECALLING',_utf8mb4'RETURNED_TO_HQ',_utf8mb4'COMPLETED',_utf8mb4'CANCELED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `headquarters_inventory`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `headquarters_inventory` (
  `product_variant_id` bigint unsigned NOT NULL,
  `on_hand_quantity` int unsigned NOT NULL DEFAULT '0',
  `reserved_quantity` int unsigned NOT NULL DEFAULT '0',
  `defective_quantity` int unsigned NOT NULL DEFAULT '0',
  `available_quantity` int GENERATED ALWAYS AS (((`on_hand_quantity` - `reserved_quantity`) - `defective_quantity`)) STORED,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_variant_id`),
  CONSTRAINT `fk_headquarters_inventory_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_headquarters_inventory_quantities` CHECK (((`reserved_quantity` + `defective_quantity`) <= `on_hand_quantity`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inquiries`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inquiries` (
  `inquiry_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `product_id` bigint unsigned DEFAULT NULL,
  `inquiry_type` varchar(30) NOT NULL,
  `title` varchar(150) NOT NULL,
  `inquiry_content` text NOT NULL,
  `inquiry_status` varchar(20) NOT NULL DEFAULT 'OPEN',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inquiry_id`),
  KEY `idx_inquiries_customer` (`customer_id`),
  KEY `idx_inquiries_product` (`product_id`),
  CONSTRAINT `fk_inquiries_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_inquiries_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_inquiries_status` CHECK ((`inquiry_status` in (_utf8mb4'OPEN',_utf8mb4'ANSWERED',_utf8mb4'CLOSED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inquiry_responses`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inquiry_responses` (
  `inquiry_response_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `inquiry_id` bigint unsigned NOT NULL,
  `employee_id` bigint unsigned NOT NULL,
  `response_content` text NOT NULL,
  `responded_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inquiry_response_id`),
  KEY `idx_responses_inquiry` (`inquiry_id`),
  KEY `idx_responses_employee` (`employee_id`),
  CONSTRAINT `fk_responses_employee` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_responses_inquiry` FOREIGN KEY (`inquiry_id`) REFERENCES `inquiries` (`inquiry_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inventory_movements`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_movements` (
  `inventory_movement_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `product_variant_id` bigint unsigned NOT NULL,
  `movement_type` varchar(30) NOT NULL,
  `on_hand_delta` int NOT NULL DEFAULT '0',
  `reserved_delta` int NOT NULL DEFAULT '0',
  `defective_delta` int NOT NULL DEFAULT '0',
  `on_hand_after` int unsigned NOT NULL,
  `reserved_after` int unsigned NOT NULL,
  `defective_after` int unsigned NOT NULL,
  `reference_type` varchar(30) DEFAULT NULL,
  `reference_id` bigint unsigned DEFAULT NULL,
  `idempotency_key` varchar(100) NOT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `created_by_employee_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`inventory_movement_id`),
  UNIQUE KEY `uq_inventory_movements_idempotency` (`idempotency_key`),
  KEY `idx_inventory_movements_variant_time` (`product_variant_id`,`created_at`),
  KEY `idx_inventory_movements_reference` (`reference_type`,`reference_id`),
  KEY `idx_inventory_movements_employee` (`created_by_employee_id`),
  CONSTRAINT `fk_inventory_movements_employee` FOREIGN KEY (`created_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_inventory_movements_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_inventory_movements_after` CHECK (((`reserved_after` + `defective_after`) <= `on_hand_after`)),
  CONSTRAINT `chk_inventory_movements_delta` CHECK (((`on_hand_delta` <> 0) or (`reserved_delta` <> 0) or (`defective_delta` <> 0))),
  CONSTRAINT `chk_inventory_movements_reference` CHECK ((((`reference_type` is null) and (`reference_id` is null)) or ((`reference_type` is not null) and (`reference_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inventory_policies`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_policies` (
  `product_variant_id` bigint unsigned NOT NULL,
  `initial_stock_quantity` int unsigned NOT NULL,
  `reorder_threshold_percent` decimal(5,2) NOT NULL DEFAULT '30.00',
  `reorder_quantity` int unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_variant_id`),
  CONSTRAINT `fk_inventory_policies_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_inventory_policies_initial_quantity` CHECK ((`initial_stock_quantity` > 0)),
  CONSTRAINT `chk_inventory_policies_reorder_quantity` CHECK ((`reorder_quantity` > 0)),
  CONSTRAINT `chk_inventory_policies_threshold` CHECK (((`reorder_threshold_percent` > 0) and (`reorder_threshold_percent` < 100)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `inventory_reservations`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_reservations` (
  `inventory_reservation_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `order_item_id` bigint unsigned NOT NULL,
  `product_variant_id` bigint unsigned NOT NULL,
  `reserved_quantity` int unsigned NOT NULL,
  `reservation_status` varchar(20) NOT NULL DEFAULT 'RESERVED',
  `expires_at` datetime NOT NULL,
  `consumed_at` datetime DEFAULT NULL,
  `released_at` datetime DEFAULT NULL,
  `release_reason` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`inventory_reservation_id`),
  UNIQUE KEY `uq_inventory_reservations_order_item` (`order_item_id`),
  KEY `idx_inventory_reservations_order_status` (`order_id`,`reservation_status`),
  KEY `idx_inventory_reservations_variant_status` (`product_variant_id`,`reservation_status`),
  KEY `idx_inventory_reservations_expiry` (`reservation_status`,`expires_at`),
  KEY `fk_inventory_reservations_order_item_order` (`order_item_id`,`order_id`),
  CONSTRAINT `fk_inventory_reservations_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_inventory_reservations_order_item_order` FOREIGN KEY (`order_item_id`, `order_id`) REFERENCES `order_items` (`order_item_id`, `order_id`),
  CONSTRAINT `fk_inventory_reservations_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_inventory_reservations_consumed_at` CHECK (((`reservation_status` <> _utf8mb4'CONSUMED') or (`consumed_at` is not null))),
  CONSTRAINT `chk_inventory_reservations_quantity` CHECK ((`reserved_quantity` > 0)),
  CONSTRAINT `chk_inventory_reservations_released_at` CHECK (((`reservation_status` not in (_utf8mb4'RELEASED',_utf8mb4'EXPIRED')) or (`released_at` is not null))),
  CONSTRAINT `chk_inventory_reservations_status` CHECK ((`reservation_status` in (_utf8mb4'RESERVED',_utf8mb4'CONSUMED',_utf8mb4'RELEASED',_utf8mb4'EXPIRED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `manufacturers`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `manufacturers` (
  `manufacturer_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `manufacturer_name` varchar(100) NOT NULL,
  `contact_name` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`manufacturer_id`),
  UNIQUE KEY `uq_manufacturers_name` (`manufacturer_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `membership_assessments`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `membership_assessments` (
  `membership_assessment_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `membership_tier_id` bigint unsigned NOT NULL,
  `benefit_month` date NOT NULL COMMENT 'First day of the month',
  `calculation_started_at` date NOT NULL,
  `calculation_ended_at` date NOT NULL,
  `confirmed_purchase_amount` int unsigned NOT NULL DEFAULT '0',
  `canceled_amount` int unsigned NOT NULL DEFAULT '0',
  `returned_amount` int unsigned NOT NULL DEFAULT '0',
  `net_purchase_amount` int unsigned NOT NULL DEFAULT '0',
  `assessed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`membership_assessment_id`),
  UNIQUE KEY `uq_membership_assessments_customer_month` (`customer_id`,`benefit_month`),
  KEY `idx_membership_assessments_tier` (`membership_tier_id`),
  CONSTRAINT `fk_membership_assessments_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_membership_assessments_tier` FOREIGN KEY (`membership_tier_id`) REFERENCES `membership_tiers` (`membership_tier_id`),
  CONSTRAINT `chk_membership_assessments_amount` CHECK ((((`net_purchase_amount` + `canceled_amount`) + `returned_amount`) = `confirmed_purchase_amount`)),
  CONSTRAINT `chk_membership_assessments_month` CHECK ((dayofmonth(`benefit_month`) = 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `membership_coupon_rules`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `membership_coupon_rules` (
  `membership_tier_id` bigint unsigned NOT NULL,
  `coupon_definition_id` bigint unsigned NOT NULL,
  `monthly_quantity` tinyint unsigned NOT NULL,
  PRIMARY KEY (`membership_tier_id`,`coupon_definition_id`),
  KEY `fk_membership_coupon_rules_coupon` (`coupon_definition_id`),
  CONSTRAINT `fk_membership_coupon_rules_coupon` FOREIGN KEY (`coupon_definition_id`) REFERENCES `coupon_definitions` (`coupon_definition_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_membership_coupon_rules_tier` FOREIGN KEY (`membership_tier_id`) REFERENCES `membership_tiers` (`membership_tier_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_membership_coupon_rules_quantity` CHECK ((`monthly_quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `membership_tiers`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `membership_tiers` (
  `membership_tier_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `tier_code` varchar(20) NOT NULL,
  `tier_name` varchar(50) NOT NULL,
  `minimum_amount` int unsigned NOT NULL,
  `maximum_amount_exclusive` int unsigned DEFAULT NULL,
  `sort_order` tinyint unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`membership_tier_id`),
  UNIQUE KEY `uq_membership_tiers_code` (`tier_code`),
  UNIQUE KEY `uq_membership_tiers_sort_order` (`sort_order`),
  CONSTRAINT `chk_membership_tiers_range` CHECK (((`maximum_amount_exclusive` is null) or (`maximum_amount_exclusive` > `minimum_amount`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_items` (
  `order_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `product_variant_id` bigint unsigned NOT NULL,
  `product_name` varchar(150) NOT NULL,
  `product_code` varchar(64) NOT NULL,
  `color_name` varchar(50) NOT NULL,
  `size_mm` smallint unsigned NOT NULL,
  `unit_price` int unsigned NOT NULL,
  `quantity` int unsigned NOT NULL,
  `line_total` int unsigned GENERATED ALWAYS AS ((`unit_price` * `quantity`)) STORED,
  PRIMARY KEY (`order_item_id`),
  UNIQUE KEY `uq_order_items_variant` (`order_id`,`product_variant_id`),
  UNIQUE KEY `uq_order_items_id_order` (`order_item_id`,`order_id`),
  KEY `idx_order_items_variant` (`product_variant_id`),
  CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_order_items_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_order_items_quantity` CHECK ((`quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `order_status_history`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `order_status_history` (
  `order_status_history_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `previous_status` varchar(30) DEFAULT NULL,
  `new_status` varchar(30) NOT NULL,
  `change_source` varchar(30) NOT NULL,
  `change_reason` varchar(255) DEFAULT NULL,
  `actor_type` varchar(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_customer_id` bigint unsigned DEFAULT NULL,
  `actor_employee_id` bigint unsigned DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`order_status_history_id`),
  KEY `idx_order_status_history_order_time` (`order_id`,`changed_at`),
  KEY `idx_order_status_history_customer` (`actor_customer_id`),
  KEY `idx_order_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_order_status_history_customer` FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_order_status_history_employee` FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_order_status_history_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_order_status_history_actor` CHECK ((((`actor_type` = _utf8mb4'SYSTEM') and (`actor_customer_id` is null) and (`actor_employee_id` is null)) or ((`actor_type` = _utf8mb4'CUSTOMER') and (`actor_customer_id` is not null) and (`actor_employee_id` is null)) or ((`actor_type` = _utf8mb4'EMPLOYEE') and (`actor_customer_id` is null) and (`actor_employee_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `orders`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `orders` (
  `order_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_number` varchar(32) NOT NULL,
  `order_request_key` varchar(100) DEFAULT NULL,
  `customer_id` bigint unsigned NOT NULL,
  `pickup_branch_id` bigint unsigned DEFAULT NULL,
  `fulfillment_type` varchar(20) NOT NULL,
  `order_status` varchar(30) NOT NULL DEFAULT 'PENDING_PAYMENT',
  `subtotal_amount` int unsigned NOT NULL,
  `coupon_discount` int unsigned NOT NULL DEFAULT '0',
  `points_used` int unsigned NOT NULL DEFAULT '0',
  `paid_total` int unsigned NOT NULL,
  `ordered_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `purchase_confirmed_at` datetime DEFAULT NULL,
  `canceled_at` datetime DEFAULT NULL,
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `uq_orders_number` (`order_number`),
  UNIQUE KEY `uq_orders_request_key` (`order_request_key`),
  KEY `idx_orders_customer_time` (`customer_id`,`ordered_at`),
  KEY `idx_orders_pickup_branch` (`pickup_branch_id`),
  CONSTRAINT `fk_orders_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_orders_pickup_branch` FOREIGN KEY (`pickup_branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `chk_orders_amount` CHECK ((((`paid_total` + `coupon_discount`) + `points_used`) = `subtotal_amount`)),
  CONSTRAINT `chk_orders_branch` CHECK ((((`fulfillment_type` = _utf8mb4'PICKUP') and (`pickup_branch_id` is not null)) or ((`fulfillment_type` = _utf8mb4'DELIVERY') and (`pickup_branch_id` is null)))),
  CONSTRAINT `chk_orders_fulfillment` CHECK ((`fulfillment_type` in (_utf8mb4'DELIVERY',_utf8mb4'PICKUP'))),
  CONSTRAINT `chk_orders_status` CHECK ((`order_status` in (_utf8mb4'PENDING_PAYMENT',_utf8mb4'PAID',_utf8mb4'PREPARING',_utf8mb4'SHIPPING',_utf8mb4'READY_FOR_PICKUP',_utf8mb4'COMPLETED',_utf8mb4'CANCELED',_utf8mb4'REFUNDED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `outbox_events`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `outbox_events` (
  `outbox_event_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `aggregate_type` varchar(30) NOT NULL,
  `aggregate_id` bigint unsigned NOT NULL,
  `event_type` varchar(50) NOT NULL,
  `payload` json NOT NULL,
  `event_status` varchar(20) NOT NULL DEFAULT 'PENDING',
  `idempotency_key` varchar(150) NOT NULL,
  `attempt_count` smallint unsigned NOT NULL DEFAULT '0',
  `next_attempt_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processing_started_at` datetime DEFAULT NULL,
  `published_at` datetime DEFAULT NULL,
  `last_error` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`outbox_event_id`),
  UNIQUE KEY `uq_outbox_events_idempotency` (`idempotency_key`),
  KEY `idx_outbox_events_delivery` (`event_status`,`next_attempt_at`,`outbox_event_id`),
  KEY `idx_outbox_events_aggregate` (`aggregate_type`,`aggregate_id`,`outbox_event_id`),
  CONSTRAINT `chk_outbox_events_aggregate_type` CHECK ((`aggregate_type` in (_utf8mb4'ORDER',_utf8mb4'FULFILLMENT',_utf8mb4'PICKUP',_utf8mb4'INVENTORY'))),
  CONSTRAINT `chk_outbox_events_attempt_count` CHECK ((`attempt_count` >= 0)),
  CONSTRAINT `chk_outbox_events_published_at` CHECK (((`event_status` <> _utf8mb4'PUBLISHED') or (`published_at` is not null))),
  CONSTRAINT `chk_outbox_events_status` CHECK ((`event_status` in (_utf8mb4'PENDING',_utf8mb4'PROCESSING',_utf8mb4'PUBLISHED',_utf8mb4'FAILED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `payments`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `payments` (
  `payment_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `payment_method` varchar(30) NOT NULL,
  `payment_status` varchar(20) NOT NULL DEFAULT 'PENDING',
  `payment_amount` int unsigned NOT NULL,
  `transaction_key` varchar(100) DEFAULT NULL,
  `paid_at` datetime DEFAULT NULL,
  PRIMARY KEY (`payment_id`),
  UNIQUE KEY `uq_payments_id_order` (`payment_id`,`order_id`),
  UNIQUE KEY `uq_payments_transaction_key` (`transaction_key`),
  KEY `idx_payments_order` (`order_id`),
  CONSTRAINT `fk_payments_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_payments_status` CHECK ((`payment_status` in (_utf8mb4'PENDING',_utf8mb4'PAID',_utf8mb4'FAILED',_utf8mb4'CANCELED',_utf8mb4'PARTIALLY_REFUNDED',_utf8mb4'REFUNDED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `permissions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `permissions` (
  `permission_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `permission_code` varchar(80) NOT NULL,
  `permission_name` varchar(120) NOT NULL,
  PRIMARY KEY (`permission_id`),
  UNIQUE KEY `uq_permissions_code` (`permission_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pickup_holdings`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pickup_holdings` (
  `pickup_holding_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `fulfillment_item_id` bigint unsigned NOT NULL,
  `branch_id` bigint unsigned NOT NULL,
  `holding_status` varchar(30) NOT NULL DEFAULT 'AWAITING_ARRIVAL',
  `quantity` int unsigned NOT NULL,
  `received_at` datetime DEFAULT NULL,
  `ready_at` datetime DEFAULT NULL,
  `picked_up_at` datetime DEFAULT NULL,
  `recalled_at` datetime DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`pickup_holding_id`),
  UNIQUE KEY `uq_pickup_holdings_fulfillment_item` (`fulfillment_item_id`),
  KEY `idx_pickup_holdings_branch_status` (`branch_id`,`holding_status`),
  CONSTRAINT `fk_pickup_holdings_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_pickup_holdings_fulfillment_item` FOREIGN KEY (`fulfillment_item_id`) REFERENCES `fulfillment_items` (`fulfillment_item_id`),
  CONSTRAINT `chk_pickup_holdings_quantity` CHECK ((`quantity` > 0)),
  CONSTRAINT `chk_pickup_holdings_status` CHECK ((`holding_status` in (_utf8mb4'AWAITING_ARRIVAL',_utf8mb4'INSPECTING',_utf8mb4'READY_FOR_PICKUP',_utf8mb4'PICKED_UP',_utf8mb4'RECALLING',_utf8mb4'RETURNED_TO_HQ',_utf8mb4'DAMAGED',_utf8mb4'CANCELED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pickup_reminders`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pickup_reminders` (
  `pickup_reminder_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `pickup_id` bigint unsigned NOT NULL,
  `reminder_type` varchar(30) NOT NULL,
  `scheduled_at` datetime NOT NULL,
  `sent_at` datetime DEFAULT NULL,
  `delivery_status` varchar(20) NOT NULL DEFAULT 'PENDING',
  `firebase_notification_id` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`pickup_reminder_id`),
  UNIQUE KEY `uq_pickup_reminders_type` (`pickup_id`,`reminder_type`),
  CONSTRAINT `fk_pickup_reminders_pickup` FOREIGN KEY (`pickup_id`) REFERENCES `pickups` (`pickup_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_pickup_reminders_status` CHECK ((`delivery_status` in (_utf8mb4'PENDING',_utf8mb4'SENT',_utf8mb4'FAILED',_utf8mb4'CANCELED'))),
  CONSTRAINT `chk_pickup_reminders_type` CHECK ((`reminder_type` in (_utf8mb4'ARRIVAL',_utf8mb4'WEEK_PASSED',_utf8mb4'PRE_RECALL',_utf8mb4'RECALL_PROCESSED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pickup_retention_policies`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pickup_retention_policies` (
  `pickup_retention_policy_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `policy_name` varchar(100) NOT NULL,
  `effective_from` date NOT NULL,
  `effective_to` date DEFAULT NULL,
  `holding_days` tinyint unsigned NOT NULL DEFAULT '14',
  `week_reminder_after_days` tinyint unsigned NOT NULL DEFAULT '7',
  `pre_recall_notice_before_days` tinyint unsigned NOT NULL DEFAULT '0',
  `recall_after_deadline_days` tinyint unsigned NOT NULL DEFAULT '1',
  PRIMARY KEY (`pickup_retention_policy_id`),
  UNIQUE KEY `uq_pickup_retention_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_pickup_retention_policies_days` CHECK (((`holding_days` > 0) and (`week_reminder_after_days` < `holding_days`) and (`pre_recall_notice_before_days` < `holding_days`) and (`recall_after_deadline_days` > 0))),
  CONSTRAINT `chk_pickup_retention_policies_period` CHECK (((`effective_to` is null) or (`effective_to` >= `effective_from`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pickup_status_history`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pickup_status_history` (
  `pickup_status_history_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `pickup_id` bigint unsigned NOT NULL,
  `previous_status` varchar(30) DEFAULT NULL,
  `new_status` varchar(30) NOT NULL,
  `change_source` varchar(30) NOT NULL,
  `change_reason` varchar(255) DEFAULT NULL,
  `actor_type` varchar(20) NOT NULL DEFAULT 'SYSTEM',
  `actor_customer_id` bigint unsigned DEFAULT NULL,
  `actor_employee_id` bigint unsigned DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`pickup_status_history_id`),
  KEY `idx_pickup_status_history_time` (`pickup_id`,`changed_at`),
  KEY `idx_pickup_status_history_customer` (`actor_customer_id`),
  KEY `idx_pickup_status_history_employee` (`actor_employee_id`),
  CONSTRAINT `fk_pickup_status_history_customer` FOREIGN KEY (`actor_customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_pickup_status_history_employee` FOREIGN KEY (`actor_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_pickup_status_history_pickup` FOREIGN KEY (`pickup_id`) REFERENCES `pickups` (`pickup_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_pickup_status_history_actor` CHECK ((((`actor_type` = _utf8mb4'SYSTEM') and (`actor_customer_id` is null) and (`actor_employee_id` is null)) or ((`actor_type` = _utf8mb4'CUSTOMER') and (`actor_customer_id` is not null) and (`actor_employee_id` is null)) or ((`actor_type` = _utf8mb4'EMPLOYEE') and (`actor_customer_id` is null) and (`actor_employee_id` is not null))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `pickups`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pickups` (
  `pickup_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `pickup_retention_policy_id` bigint unsigned DEFAULT NULL,
  `branch_id` bigint unsigned NOT NULL,
  `handled_by_employee_id` bigint unsigned DEFAULT NULL,
  `pickup_status` varchar(30) NOT NULL DEFAULT 'PREPARING',
  `arrived_at` datetime DEFAULT NULL,
  `ready_at` datetime DEFAULT NULL,
  `pickup_deadline_at` datetime DEFAULT NULL,
  `picked_up_at` datetime DEFAULT NULL,
  `recalled_at` datetime DEFAULT NULL,
  PRIMARY KEY (`pickup_id`),
  UNIQUE KEY `uq_pickups_order` (`order_id`),
  KEY `idx_pickups_branch` (`branch_id`),
  KEY `idx_pickups_employee` (`handled_by_employee_id`),
  KEY `idx_pickups_retention_policy` (`pickup_retention_policy_id`),
  CONSTRAINT `fk_pickups_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_pickups_employee` FOREIGN KEY (`handled_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_pickups_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_pickups_retention_policy` FOREIGN KEY (`pickup_retention_policy_id`) REFERENCES `pickup_retention_policies` (`pickup_retention_policy_id`),
  CONSTRAINT `chk_pickups_status` CHECK ((`pickup_status` in (_utf8mb4'PREPARING',_utf8mb4'READY_FOR_PICKUP',_utf8mb4'COMPLETED',_utf8mb4'CANCELED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `point_lots`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `point_lots` (
  `point_lot_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `source_transaction_id` bigint unsigned NOT NULL,
  `original_amount` int unsigned NOT NULL,
  `remaining_amount` int unsigned NOT NULL,
  `lot_status` varchar(20) NOT NULL DEFAULT 'AVAILABLE',
  `earned_at` datetime NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_lot_id`),
  UNIQUE KEY `uq_point_lots_source_transaction` (`source_transaction_id`),
  KEY `idx_point_lots_customer_expiry` (`customer_id`,`lot_status`,`expires_at`,`point_lot_id`),
  CONSTRAINT `fk_point_lots_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_point_lots_source_transaction` FOREIGN KEY (`source_transaction_id`) REFERENCES `point_transactions` (`point_transaction_id`),
  CONSTRAINT `chk_point_lots_amounts` CHECK (((`original_amount` > 0) and (`remaining_amount` <= `original_amount`))),
  CONSTRAINT `chk_point_lots_expiry` CHECK ((`expires_at` > `earned_at`)),
  CONSTRAINT `chk_point_lots_status` CHECK ((`lot_status` in (_utf8mb4'AVAILABLE',_utf8mb4'CONSUMED',_utf8mb4'EXPIRED',_utf8mb4'REVOKED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `point_policies`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `point_policies` (
  `point_policy_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `policy_name` varchar(100) NOT NULL,
  `expiration_years` tinyint unsigned NOT NULL DEFAULT '1',
  `use_order` varchar(30) NOT NULL DEFAULT 'EARLIEST_EXPIRY',
  `effective_from` datetime NOT NULL,
  `effective_to` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_policy_id`),
  CONSTRAINT `chk_point_policies_expiration` CHECK ((`expiration_years` > 0)),
  CONSTRAINT `chk_point_policies_period` CHECK (((`effective_to` is null) or (`effective_to` > `effective_from`))),
  CONSTRAINT `chk_point_policies_use_order` CHECK ((`use_order` = _utf8mb4'EARLIEST_EXPIRY'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `point_transactions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `point_transactions` (
  `point_transaction_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `transaction_type` varchar(20) NOT NULL,
  `point_amount` int NOT NULL,
  `balance_after` int unsigned NOT NULL,
  `order_id` bigint unsigned DEFAULT NULL,
  `review_id` bigint unsigned DEFAULT NULL,
  `idempotency_key` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `expires_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_transaction_id`),
  UNIQUE KEY `uq_point_transactions_idempotency` (`idempotency_key`),
  KEY `idx_point_transactions_customer_time` (`customer_id`,`created_at`),
  KEY `idx_point_transactions_order` (`order_id`),
  KEY `idx_point_transactions_review` (`review_id`),
  CONSTRAINT `fk_point_transactions_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_point_transactions_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `fk_point_transactions_review` FOREIGN KEY (`review_id`) REFERENCES `reviews` (`review_id`),
  CONSTRAINT `chk_point_transactions_amount` CHECK ((`point_amount` <> 0)),
  CONSTRAINT `chk_point_transactions_type` CHECK ((`transaction_type` in (_utf8mb4'EARN',_utf8mb4'USE',_utf8mb4'EXPIRE',_utf8mb4'REVOKE',_utf8mb4'REFUND',_utf8mb4'ADJUST')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `point_usage_details`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `point_usage_details` (
  `point_usage_detail_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `usage_transaction_id` bigint unsigned NOT NULL,
  `point_lot_id` bigint unsigned NOT NULL,
  `used_amount` int unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`point_usage_detail_id`),
  UNIQUE KEY `uq_point_usage_transaction_lot` (`usage_transaction_id`,`point_lot_id`),
  KEY `idx_point_usage_lot` (`point_lot_id`),
  CONSTRAINT `fk_point_usage_lot` FOREIGN KEY (`point_lot_id`) REFERENCES `point_lots` (`point_lot_id`),
  CONSTRAINT `fk_point_usage_transaction` FOREIGN KEY (`usage_transaction_id`) REFERENCES `point_transactions` (`point_transaction_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_point_usage_amount` CHECK ((`used_amount` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `point_wallets`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `point_wallets` (
  `customer_id` bigint unsigned NOT NULL,
  `point_balance` int unsigned NOT NULL DEFAULT '0',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`),
  CONSTRAINT `fk_point_wallets_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `product_images`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `product_images` (
  `product_image_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `product_id` bigint unsigned NOT NULL,
  `color_code` varchar(20) DEFAULT NULL,
  `image_url` varchar(2048) NOT NULL,
  `sort_order` smallint unsigned NOT NULL DEFAULT '0',
  `is_primary` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`product_image_id`),
  KEY `idx_product_images_product_color` (`product_id`,`color_code`),
  CONSTRAINT `fk_product_images_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `product_variants`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `product_variants` (
  `product_variant_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `product_id` bigint unsigned NOT NULL,
  `product_code` varchar(64) NOT NULL COMMENT 'SKU: NK-M-SN-0001-BLK-250',
  `color_code` varchar(20) NOT NULL,
  `color_name` varchar(50) NOT NULL,
  `size_mm` smallint unsigned NOT NULL,
  `additional_price` int NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`product_variant_id`),
  UNIQUE KEY `uq_variants_product_code` (`product_code`),
  UNIQUE KEY `uq_variants_option` (`product_id`,`color_code`,`size_mm`),
  CONSTRAINT `fk_variants_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`),
  CONSTRAINT `chk_variants_size` CHECK ((`size_mm` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `product_views`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `product_views` (
  `product_view_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint unsigned NOT NULL,
  `product_id` bigint unsigned NOT NULL,
  `viewed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_view_id`),
  KEY `idx_views_customer_time` (`customer_id`,`viewed_at`),
  KEY `idx_views_product` (`product_id`),
  CONSTRAINT `fk_views_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_views_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `products`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `products` (
  `product_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `brand_id` bigint unsigned NOT NULL,
  `category_id` bigint unsigned NOT NULL,
  `manufacturer_id` bigint unsigned DEFAULT NULL,
  `model_code` varchar(40) NOT NULL COMMENT 'Example: NK-M-SN-0001',
  `product_name` varchar(150) NOT NULL,
  `gender_code` varchar(10) NOT NULL,
  `product_description` text,
  `price` int unsigned NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`product_id`),
  UNIQUE KEY `uq_products_model_code` (`model_code`),
  KEY `idx_products_brand` (`brand_id`),
  KEY `idx_products_category` (`category_id`),
  KEY `idx_products_manufacturer` (`manufacturer_id`),
  CONSTRAINT `fk_products_brand` FOREIGN KEY (`brand_id`) REFERENCES `brands` (`brand_id`),
  CONSTRAINT `fk_products_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  CONSTRAINT `fk_products_manufacturer` FOREIGN KEY (`manufacturer_id`) REFERENCES `manufacturers` (`manufacturer_id`),
  CONSTRAINT `chk_products_gender` CHECK ((`gender_code` in (_utf8mb4'M',_utf8mb4'W',_utf8mb4'U',_utf8mb4'K')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `purchase_approvals`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `purchase_approvals` (
  `purchase_approval_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `purchase_requisition_id` bigint unsigned NOT NULL,
  `approval_sequence` tinyint unsigned NOT NULL DEFAULT '1',
  `required_role_id` bigint unsigned NOT NULL,
  `approver_employee_id` bigint unsigned DEFAULT NULL,
  `approval_status` varchar(20) NOT NULL,
  `approval_comment` text,
  `decided_at` datetime DEFAULT NULL,
  PRIMARY KEY (`purchase_approval_id`),
  UNIQUE KEY `uq_purchase_approvals_requisition_sequence` (`purchase_requisition_id`,`approval_sequence`),
  KEY `idx_approvals_employee` (`approver_employee_id`),
  KEY `idx_purchase_approvals_required_role` (`required_role_id`),
  CONSTRAINT `fk_approvals_employee` FOREIGN KEY (`approver_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_approvals_requisition` FOREIGN KEY (`purchase_requisition_id`) REFERENCES `purchase_requisitions` (`purchase_requisition_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_purchase_approvals_required_role` FOREIGN KEY (`required_role_id`) REFERENCES `roles` (`role_id`),
  CONSTRAINT `chk_approvals_decision_fields` CHECK ((((`approval_status` = _utf8mb4'PENDING') and (`approver_employee_id` is null) and (`decided_at` is null)) or ((`approval_status` in (_utf8mb4'APPROVED',_utf8mb4'REJECTED')) and (`approver_employee_id` is not null) and (`decided_at` is not null)) or ((`approval_status` = _utf8mb4'WAIVED') and (`decided_at` is not null)))),
  CONSTRAINT `chk_approvals_status` CHECK ((`approval_status` in (_utf8mb4'PENDING',_utf8mb4'APPROVED',_utf8mb4'REJECTED',_utf8mb4'WAIVED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `purchase_requisition_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `purchase_requisition_items` (
  `purchase_requisition_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `purchase_requisition_id` bigint unsigned NOT NULL,
  `product_variant_id` bigint unsigned NOT NULL,
  `requested_quantity` int unsigned NOT NULL,
  PRIMARY KEY (`purchase_requisition_item_id`),
  UNIQUE KEY `uq_requisition_items_variant` (`purchase_requisition_id`,`product_variant_id`),
  KEY `idx_requisition_items_variant` (`product_variant_id`),
  CONSTRAINT `fk_requisition_items_requisition` FOREIGN KEY (`purchase_requisition_id`) REFERENCES `purchase_requisitions` (`purchase_requisition_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_requisition_items_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`),
  CONSTRAINT `chk_requisition_items_quantity` CHECK ((`requested_quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `purchase_requisitions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `purchase_requisitions` (
  `purchase_requisition_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `requested_by_employee_id` bigint unsigned NOT NULL,
  `branch_id` bigint unsigned DEFAULT NULL,
  `approval_workflow_id` bigint unsigned NOT NULL,
  `title` varchar(150) NOT NULL,
  `reason` text NOT NULL,
  `requisition_status` varchar(30) NOT NULL DEFAULT 'DRAFT',
  `submitted_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`purchase_requisition_id`),
  KEY `idx_requisitions_employee` (`requested_by_employee_id`),
  KEY `idx_requisitions_branch` (`branch_id`),
  KEY `idx_requisitions_workflow` (`approval_workflow_id`),
  CONSTRAINT `fk_requisitions_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_requisitions_employee` FOREIGN KEY (`requested_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_requisitions_workflow` FOREIGN KEY (`approval_workflow_id`) REFERENCES `approval_workflows` (`approval_workflow_id`),
  CONSTRAINT `chk_requisitions_status` CHECK ((`requisition_status` in (_utf8mb4'DRAFT',_utf8mb4'SUBMITTED',_utf8mb4'PENDING_TEAM_LEAD',_utf8mb4'PENDING_DIRECTOR',_utf8mb4'APPROVED',_utf8mb4'REJECTED',_utf8mb4'ORDERED',_utf8mb4'CANCELED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `refund_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `refund_items` (
  `refund_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `refund_id` bigint unsigned NOT NULL,
  `order_id` bigint unsigned NOT NULL,
  `order_item_id` bigint unsigned NOT NULL,
  `quantity` int unsigned NOT NULL,
  `refund_amount` int unsigned NOT NULL,
  PRIMARY KEY (`refund_item_id`),
  UNIQUE KEY `uq_refund_items_order_item` (`refund_id`,`order_item_id`),
  KEY `idx_refund_items_order_item` (`order_item_id`),
  KEY `fk_refund_items_refund_order` (`refund_id`,`order_id`),
  KEY `fk_refund_items_order_item_order` (`order_item_id`,`order_id`),
  CONSTRAINT `fk_refund_items_order_item_order` FOREIGN KEY (`order_item_id`, `order_id`) REFERENCES `order_items` (`order_item_id`, `order_id`),
  CONSTRAINT `fk_refund_items_refund_order` FOREIGN KEY (`refund_id`, `order_id`) REFERENCES `refunds` (`refund_id`, `order_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_refund_items_amount` CHECK ((`refund_amount` >= 0)),
  CONSTRAINT `chk_refund_items_quantity` CHECK ((`quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `refunds`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `refunds` (
  `refund_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `refund_number` varchar(32) NOT NULL,
  `payment_id` bigint unsigned NOT NULL,
  `order_id` bigint unsigned NOT NULL,
  `return_request_id` bigint unsigned DEFAULT NULL,
  `refund_type` varchar(20) NOT NULL,
  `refund_status` varchar(20) NOT NULL DEFAULT 'REQUESTED',
  `refund_amount` int unsigned NOT NULL,
  `idempotency_key` varchar(100) NOT NULL,
  `provider_refund_key` varchar(100) DEFAULT NULL,
  `failure_code` varchar(50) DEFAULT NULL,
  `failure_message` varchar(255) DEFAULT NULL,
  `retry_count` smallint unsigned NOT NULL DEFAULT '0',
  `requested_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processing_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `failed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`refund_id`),
  UNIQUE KEY `uq_refunds_number` (`refund_number`),
  UNIQUE KEY `uq_refunds_idempotency` (`idempotency_key`),
  UNIQUE KEY `uq_refunds_id_order` (`refund_id`,`order_id`),
  UNIQUE KEY `uq_refunds_provider_key` (`provider_refund_key`),
  KEY `idx_refunds_payment_status` (`payment_id`,`refund_status`),
  KEY `idx_refunds_return_request` (`return_request_id`),
  KEY `idx_refunds_order_status` (`order_id`,`refund_status`),
  KEY `fk_refunds_payment_order` (`payment_id`,`order_id`),
  CONSTRAINT `fk_refunds_payment_order` FOREIGN KEY (`payment_id`, `order_id`) REFERENCES `payments` (`payment_id`, `order_id`),
  CONSTRAINT `fk_refunds_return_request` FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`),
  CONSTRAINT `chk_refunds_amount` CHECK ((`refund_amount` >= 0)),
  CONSTRAINT `chk_refunds_completed_at` CHECK (((`refund_status` <> _utf8mb4'SUCCEEDED') or (`completed_at` is not null))),
  CONSTRAINT `chk_refunds_failed_at` CHECK (((`refund_status` <> _utf8mb4'FAILED') or (`failed_at` is not null))),
  CONSTRAINT `chk_refunds_retry_count` CHECK ((`retry_count` >= 0)),
  CONSTRAINT `chk_refunds_status` CHECK ((`refund_status` in (_utf8mb4'REQUESTED',_utf8mb4'PROCESSING',_utf8mb4'SUCCEEDED',_utf8mb4'FAILED',_utf8mb4'CANCELED'))),
  CONSTRAINT `chk_refunds_type` CHECK ((`refund_type` in (_utf8mb4'ORDER_CANCEL',_utf8mb4'RETURN',_utf8mb4'MANUAL_ADJUSTMENT')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `restock_subscriptions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `restock_subscriptions` (
  `customer_id` bigint unsigned NOT NULL,
  `product_variant_id` bigint unsigned NOT NULL,
  `subscribed_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`customer_id`,`product_variant_id`),
  KEY `fk_restock_variant` (`product_variant_id`),
  CONSTRAINT `fk_restock_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_restock_variant` FOREIGN KEY (`product_variant_id`) REFERENCES `product_variants` (`product_variant_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `return_items`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `return_items` (
  `return_item_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `return_request_id` bigint unsigned NOT NULL,
  `order_item_id` bigint unsigned NOT NULL,
  `quantity` int unsigned NOT NULL,
  PRIMARY KEY (`return_item_id`),
  UNIQUE KEY `uq_return_items_order_item` (`return_request_id`,`order_item_id`),
  KEY `idx_return_items_order_item` (`order_item_id`),
  CONSTRAINT `fk_return_items_order_item` FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`order_item_id`),
  CONSTRAINT `fk_return_items_request` FOREIGN KEY (`return_request_id`) REFERENCES `return_requests` (`return_request_id`) ON DELETE CASCADE,
  CONSTRAINT `chk_return_items_quantity` CHECK ((`quantity` > 0))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `return_policies`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `return_policies` (
  `return_policy_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `policy_name` varchar(100) NOT NULL,
  `effective_from` date NOT NULL,
  `effective_to` date DEFAULT NULL,
  `standard_return_days` tinyint unsigned NOT NULL DEFAULT '7',
  `requires_unworn` tinyint(1) NOT NULL DEFAULT '1',
  `requires_no_customer_damage` tinyint(1) NOT NULL DEFAULT '1',
  `requires_components_complete` tinyint(1) NOT NULL DEFAULT '1',
  `requires_packaging_intact` tinyint(1) NOT NULL DEFAULT '1',
  `allows_defect_exception` tinyint(1) NOT NULL DEFAULT '1',
  `allows_wrong_item_exception` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`return_policy_id`),
  UNIQUE KEY `uq_return_policies_effective_from` (`effective_from`),
  CONSTRAINT `chk_return_policies_days` CHECK ((`standard_return_days` > 0)),
  CONSTRAINT `chk_return_policies_period` CHECK (((`effective_to` is null) or (`effective_to` >= `effective_from`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `return_requests`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `return_requests` (
  `return_request_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_id` bigint unsigned NOT NULL,
  `customer_id` bigint unsigned NOT NULL,
  `return_policy_id` bigint unsigned DEFAULT NULL,
  `branch_id` bigint unsigned DEFAULT NULL,
  `handled_by_employee_id` bigint unsigned DEFAULT NULL,
  `return_reason_code` varchar(30) NOT NULL DEFAULT 'CUSTOMER_CHANGE',
  `request_status` varchar(30) NOT NULL DEFAULT 'REQUESTED',
  `return_reason` text NOT NULL,
  `return_deadline_at` datetime DEFAULT NULL,
  `inspection_result` varchar(30) DEFAULT NULL,
  `rejection_reason` text,
  `requested_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `processed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`return_request_id`),
  KEY `idx_returns_order` (`order_id`),
  KEY `idx_returns_customer` (`customer_id`),
  KEY `idx_returns_branch` (`branch_id`),
  KEY `idx_returns_employee` (`handled_by_employee_id`),
  KEY `idx_return_requests_policy` (`return_policy_id`),
  CONSTRAINT `fk_return_requests_policy` FOREIGN KEY (`return_policy_id`) REFERENCES `return_policies` (`return_policy_id`),
  CONSTRAINT `fk_returns_branch` FOREIGN KEY (`branch_id`) REFERENCES `branches` (`branch_id`),
  CONSTRAINT `fk_returns_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_returns_employee` FOREIGN KEY (`handled_by_employee_id`) REFERENCES `employees` (`employee_id`),
  CONSTRAINT `fk_returns_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  CONSTRAINT `chk_return_requests_reason_code` CHECK ((`return_reason_code` in (_utf8mb4'CUSTOMER_CHANGE',_utf8mb4'PRODUCT_DEFECT',_utf8mb4'WRONG_ITEM',_utf8mb4'OTHER'))),
  CONSTRAINT `chk_returns_status` CHECK ((`request_status` in (_utf8mb4'REQUESTED',_utf8mb4'APPROVED',_utf8mb4'REJECTED',_utf8mb4'COLLECTING',_utf8mb4'INSPECTING',_utf8mb4'RETURNED',_utf8mb4'COMPLETED',_utf8mb4'CANCELED')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `review_images`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `review_images` (
  `review_image_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `review_id` bigint unsigned NOT NULL,
  `image_url` varchar(2048) NOT NULL,
  `sort_order` smallint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`review_image_id`),
  KEY `idx_review_images_review` (`review_id`),
  CONSTRAINT `fk_review_images_review` FOREIGN KEY (`review_id`) REFERENCES `reviews` (`review_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `review_photo_payloads`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `review_photo_payloads` (
  `review_id` bigint unsigned NOT NULL,
  `sort_order` smallint unsigned NOT NULL,
  `photo_base64` longtext NOT NULL,
  PRIMARY KEY (`review_id`,`sort_order`),
  CONSTRAINT `fk_review_photo_payloads_review` FOREIGN KEY (`review_id`) REFERENCES `reviews` (`review_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `reviews`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `reviews` (
  `review_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_item_id` bigint unsigned NOT NULL,
  `customer_id` bigint unsigned NOT NULL,
  `rating` tinyint unsigned NOT NULL,
  `review_content` text NOT NULL,
  `fit_size` varchar(30) DEFAULT NULL,
  `fit_width` varchar(30) DEFAULT NULL,
  `fit_comfort` varchar(30) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `deleted_at` datetime DEFAULT NULL,
  PRIMARY KEY (`review_id`),
  UNIQUE KEY `uq_reviews_order_item` (`order_item_id`),
  KEY `idx_reviews_customer` (`customer_id`),
  CONSTRAINT `fk_reviews_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  CONSTRAINT `fk_reviews_order_item` FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`order_item_id`),
  CONSTRAINT `chk_reviews_rating` CHECK ((`rating` between 1 and 5))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `role_permissions`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `role_permissions` (
  `role_id` bigint unsigned NOT NULL,
  `permission_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`role_id`,`permission_id`),
  KEY `fk_role_permissions_permission` (`permission_id`),
  CONSTRAINT `fk_role_permissions_permission` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`permission_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_role_permissions_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `roles`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `roles` (
  `role_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role_code` varchar(50) NOT NULL,
  `role_name` varchar(100) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`role_id`),
  UNIQUE KEY `uq_roles_code` (`role_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed
